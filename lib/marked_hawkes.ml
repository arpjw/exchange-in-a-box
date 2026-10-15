type parameters =
  { baseline_buy : float; baseline_sell : float
  ; buy_buy : float; buy_sell : float; sell_buy : float; sell_sell : float
  ; decay : float }
type event = { time : float; side : Book.side }
type residual = { event : event; component_increment : float; total_increment : float }

let branching_radius p =
  let values = [p.baseline_buy; p.baseline_sell; p.buy_buy; p.buy_sell;
                p.sell_buy; p.sell_sell; p.decay] in
  if not (List.for_all Float.is_finite values) then Error "parameters must be finite"
  else if p.baseline_buy <= 0. || p.baseline_sell <= 0. || p.decay <= 0.
       || p.buy_buy < 0. || p.buy_sell < 0. || p.sell_buy < 0. || p.sell_sell < 0. then
    Error "baselines and decay must be positive; excitation must be nonnegative"
  else
    let a = p.buy_buy /. p.decay and b = p.buy_sell /. p.decay
    and c = p.sell_buy /. p.decay and d = p.sell_sell /. p.decay in
    if not (List.for_all Float.is_finite [a;b;c;d]) then Error "branching matrix overflow"
    else if List.exists (fun (coefficient, normalized) -> coefficient > 0. && normalized = 0.)
        [p.buy_buy,a; p.buy_sell,b; p.sell_buy,c; p.sell_sell,d] then
      Error "branching matrix underflow"
    else
      (* Square roots before multiplying avoid overflowing b*c or losing a
         tiny cross-term when the opposite direction has a huge coefficient. *)
      let rho = a /. 2. +. d /. 2.
        +. Float.hypot (a /. 2. -. d /. 2.) (sqrt b *. sqrt c) in
      if Float.is_finite rho then Ok rho else Error "spectral radius overflow"

let validate p =
  match branching_radius p with
  | Error e -> Error e
  | Ok rho when rho >= 1. -> Error "branching spectral radius must be below one"
  | Ok _ -> Ok ()

let validate_events ~horizon events =
  if not (Float.is_finite horizon) || horizon < 0. then Error "invalid horizon"
  else
    let rec loop previous = function
      | [] -> Ok ()
      | event :: rest ->
          if not (Float.is_finite event.time) || event.time < 0.
             || event.time > horizon || event.time <= previous then
            Error "event times must be finite, strictly increasing and in the horizon"
          else loop event.time rest
    in
    loop neg_infinity events

let jump p side buy sell = match side with
  | Book.Buy -> buy +. p.buy_buy, sell +. p.sell_buy
  | Book.Sell -> buy +. p.buy_sell, sell +. p.sell_sell

let integrate p dt buy sell =
  let x = p.decay *. dt in
  (* Integrate the kernel before multiplying the intensity. This avoids
     overflow in state/decay and preserves the dt limit when decay*dt
     underflows to zero. *)
  let integrated_kernel = if x = 0. then dt else -.expm1 (-.x) /. p.decay in
  p.baseline_buy *. dt +. buy *. integrated_kernel,
  p.baseline_sell *. dt +. sell *. integrated_kernel

let decay p dt buy sell =
  let factor = exp (-.p.decay *. dt) in
  buy *. factor, sell *. factor

let log_likelihood p ~horizon events =
  match validate p, validate_events ~horizon events with
  | Error e, _ | _, Error e -> Error e
  | Ok (), Ok () ->
      let rec loop previous buy sell ll = function
        | [] ->
            let ib, is = integrate p (horizon -. previous) buy sell in
            let result = ll -. ib -. is in
            if Float.is_finite result then Ok result else Error "likelihood overflow"
        | event :: rest ->
            let dt = event.time -. previous in
            let ib, is = integrate p dt buy sell in
            let buy, sell = decay p dt buy sell in
            let intensity = match event.side with
              | Book.Buy -> p.baseline_buy +. buy | Book.Sell -> p.baseline_sell +. sell in
            let buy, sell = jump p event.side buy sell in
            loop event.time buy sell (ll +. log intensity -. ib -. is) rest
      in
      loop 0. 0. 0. 0. events

let compensator_increments p events =
  let horizon = List.fold_left (fun _ e -> e.time) 0. events in
  match validate p, validate_events ~horizon events with
  | Error e, _ | _, Error e -> Error e
  | Ok (), Ok () ->
      let rec loop previous buy sell accumulated_buy accumulated_sell acc = function
        | [] -> Ok (List.rev acc)
        | event :: rest ->
            let dt = event.time -. previous in
            let ib, is = integrate p dt buy sell in
            let accumulated_buy = accumulated_buy +. ib
            and accumulated_sell = accumulated_sell +. is in
            let component_increment, accumulated_buy, accumulated_sell = match event.side with
              | Book.Buy -> accumulated_buy, 0., accumulated_sell
              | Book.Sell -> accumulated_sell, accumulated_buy, 0. in
            let total_increment = ib +. is in
            if not (List.for_all Float.is_finite
              [component_increment;total_increment;accumulated_buy;accumulated_sell]) then
              Error "compensator overflow"
            else
              let buy, sell = decay p dt buy sell in
              let buy, sell = jump p event.side buy sell in
              loop event.time buy sell accumulated_buy accumulated_sell
                ({event;component_increment;total_increment} :: acc) rest
      in
      loop 0. 0. 0. 0. 0. [] events

let simulate ~seed ~max_events ~max_candidates ~horizon p =
  match validate p, validate_events ~horizon [] with
  | Error e, _ | _, Error e -> Error e
  | Ok (), Ok () ->
      if max_events < 0 || max_candidates <= 0 then Error "invalid simulation limits"
      else if horizon = 0. then Ok []
      else
        let rng = Random.State.make [|seed|] in
        let rec loop previous buy sell count candidates acc =
          let bound = p.baseline_buy +. buy +. p.baseline_sell +. sell in
          if not (Float.is_finite bound) then Error "intensity overflow"
          else if candidates >= max_candidates then Error "simulation candidate limit exceeded"
          else
            let dt = -.log (1. -. Random.State.float rng 1.) /. bound in
            let time = previous +. dt in
            if time > horizon then Ok (List.rev acc)
            else if time <= previous then Error "simulation time resolution exhausted"
            else
              let buy, sell = decay p dt buy sell in
              let ib = p.baseline_buy +. buy and is = p.baseline_sell +. sell in
              if Random.State.float rng 1. *. bound <= ib +. is then
                if count >= max_events then Error "simulation event limit exceeded"
                else
                  let side = if Random.State.float rng 1. *. (ib +. is) < ib then Book.Buy else Book.Sell in
                  let buy, sell = jump p side buy sell in
                  loop time buy sell (count + 1) (candidates + 1) ({time;side} :: acc)
              else loop time buy sell count (candidates + 1) acc
        in
        loop 0. 0. 0. 0 0 []
