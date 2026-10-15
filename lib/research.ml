module H = Analytics.Hawkes

let validate_times ~horizon times =
  if not (Float.is_finite horizon) || horizon <= 0. then
    Error "horizon must be finite and positive"
  else
    let rec loop previous = function
      | [] -> Ok ()
      | t :: rest ->
          if not (Float.is_finite t) || t < 0. || t > horizon || t <= previous
          then Error "event times must be finite, strictly increasing and within horizon"
          else loop t rest
    in
    loop neg_infinity times

let simulate_hawkes ~seed ~max_events ~max_candidates ~horizon p =
  match H.validate p, validate_times ~horizon [] with
  | Error e, _ | _, Error e -> Error e
  | Ok (), Ok () ->
      if max_events < 0 || max_candidates <= 0 then Error "invalid simulation limits"
      else
        let rng = Random.State.make [| seed |] in
        let rec loop t state count candidates acc =
          let bound = p.H.baseline +. p.excitation *. state in
          if not (Float.is_finite bound) then Error "simulation intensity overflow"
          else if candidates >= max_candidates then Error "simulation candidate limit exceeded"
          else
            let u = 1. -. Random.State.float rng 1. in
            let dt = -.log u /. bound in
            let next = t +. dt in
            if next > horizon then Ok (List.rev acc)
            else if next <= t then Error "simulation time resolution exhausted"
            else
              let decayed = state *. exp (-.p.decay *. dt) in
              let intensity = p.baseline +. p.excitation *. decayed in
              if Random.State.float rng 1. *. bound <= intensity then
                if count >= max_events then Error "simulation event limit exceeded"
                else loop next (decayed +. 1.) (count + 1) (candidates + 1) (next :: acc)
              else loop next decayed count (candidates + 1) acc
        in
        loop 0. 0. 0 0 []

(* Evaluate directly on the test interval instead of subtracting two potentially
   large full-path likelihoods. State is the exponential excitation sum. *)
let conditional_log_likelihood p ~start ~horizon times =
  match H.validate p, validate_times ~horizon times with
  | Error e, _ | _, Error e -> Error e
  | Ok (), Ok () ->
      if not (Float.is_finite start) || start < 0. || start >= horizon then
        Error "start must be in [0,horizon)"
      else
        let rec history previous state = function
          | t :: rest when t <= start ->
              history t (state *. exp (-.p.H.decay *. (t -. previous)) +. 1.) rest
          | remaining ->
              state *. exp (-.p.decay *. (start -. previous)), remaining
        in
        let initial, remaining = history 0. 0. times in
        let integral state dt =
          p.baseline *. dt +. p.excitation /. p.decay *. state
          *. (-.expm1 (-.p.decay *. dt))
        in
        let rec score previous state acc = function
          | [] -> acc -. integral state (horizon -. previous)
          | t :: rest ->
              let dt = t -. previous in
              let decayed = state *. exp (-.p.decay *. dt) in
              let acc = acc -. integral state dt
                        +. log (p.baseline +. p.excitation *. decayed) in
              score t (decayed +. 1.) acc rest
        in
        let result = score start initial 0. remaining in
        if Float.is_finite result then Ok result else Error "likelihood overflow"

type fit =
  { parameters : H.parameters
  ; training_log_likelihood : float
  ; heldout_log_likelihood : float
  ; residual_mean : float option
  ; residual_ks : float option
  ; residual_count : int
  }

type comparison =
  { poisson : fit
  ; hawkes : fit
  ; training_events : int
  ; heldout_events : int
  ; hawkes_candidates : int
  }

let residual_summary p ~split times =
  let rec loop previous state acc = function
    | [] -> List.rev acc
    | t :: rest ->
        let dt = t -. previous in
        let residual = p.H.baseline *. dt +. p.excitation /. p.decay *. state
                       *. (-.expm1 (-.p.decay *. dt)) in
        let acc = if previous >= split then residual :: acc else acc in
        loop t (state *. exp (-.p.decay *. dt) +. 1.) acc rest
  in
  let residuals = loop 0. 0. [] times in
  let n = List.length residuals in
  if n = 0 then None, None, 0
  else
    let nf = float_of_int n in
    let sorted = List.sort Float.compare residuals in
    let rec ks i best = function
      | [] -> best
      | x :: rest ->
          let cdf = -.expm1 (-.x) in
          let distance = max (float_of_int i /. nf -. cdf)
                            (cdf -. float_of_int (i - 1) /. nf) in
          ks (i + 1) (max best distance) rest
    in
    Some (List.fold_left ( +. ) 0. residuals /. nf), Some (ks 1 0. sorted), n

let compare ~split ~horizon ~decays ~branching_ratios ~baseline_multipliers times =
  match validate_times ~horizon times with
  | Error e -> Error e
  | Ok () ->
      if not (Float.is_finite split) || split <= 0. || split >= horizon then
        Error "split must be strictly inside observation interval"
      else if decays = [] || branching_ratios = [] || baseline_multipliers = [] then
        Error "fit grids must be nonempty"
      else if not (List.for_all (fun x -> Float.is_finite x && x > 0.) decays
                   && List.for_all (fun x -> Float.is_finite x && x >= 0. && x < 1.) branching_ratios
                   && List.for_all (fun x -> Float.is_finite x && x > 0.) baseline_multipliers) then
        Error "invalid fit grid"
      else
        let training = List.filter (fun t -> t <= split) times in
        let n = List.length training in
        let heldout_n = List.length times - n in
        let rate = float_of_int n /. split in
        let grid_rate = if n = 0 then 1. /. split else rate in
        let candidates = List.concat_map (fun decay ->
          List.concat_map (fun ratio ->
            List.map (fun multiplier ->
              H.{ baseline = grid_rate *. multiplier; excitation = decay *. ratio; decay })
              baseline_multipliers) branching_ratios) decays in
        let best = List.fold_left (fun best p ->
          match H.log_likelihood p ~horizon:split training with
          | Error _ -> best
          | Ok ll when Float.is_finite ll ->
              (match best with None -> Some (p, ll)
               | Some (_, old) when ll > old -> Some (p, ll) | _ -> best)
          | Ok _ -> best) None candidates in
        match best with
        | None -> Error "no finite Hawkes grid candidate"
        | Some (p, ll) ->
            match conditional_log_likelihood p ~start:split ~horizon times with
            | Error e -> Error e
            | Ok heldout ->
                let make p training_log_likelihood heldout_log_likelihood =
                  let residual_mean, residual_ks, residual_count = residual_summary p ~split times in
                  { parameters = p; training_log_likelihood; heldout_log_likelihood
                  ; residual_mean; residual_ks; residual_count }
                in
                let poisson_train = if n = 0 then 0. else float_of_int n *. log rate -. rate *. split in
                let poisson_test =
                  if rate = 0. then (if heldout_n = 0 then 0. else neg_infinity)
                  else float_of_int heldout_n *. log rate -. rate *. (horizon -. split)
                in
                Ok { poisson = make H.{ baseline = rate; excitation = 0.; decay = 1. } poisson_train poisson_test
                   ; hawkes = make p ll heldout; training_events = n
                   ; heldout_events = heldout_n; hawkes_candidates = List.length candidates }

type impact =
  { filled_lots : int
  ; vwap : float
  ; slippage_ticks : float
  ; effective_spread_ticks : float
  ; realized_spread_ticks : float
  ; midpoint_impact_ticks : float
  }

let impact ~side ~arrival_mid ~later_mid trades =
  if not (Float.is_finite arrival_mid && Float.is_finite later_mid)
     || arrival_mid <= 0. || later_mid <= 0. then Error "invalid midpoint"
  else
    let rec accumulate lots notional = function
      | [] -> Ok (lots, notional)
      | (trade : Book.trade) :: rest ->
          if trade.quantity <= 0 || trade.price <= 0 then Error "invalid fill"
          else if lots > max_int - trade.quantity then Error "fill quantity overflow"
          else accumulate (lots + trade.quantity)
              (notional +. float_of_int trade.price *. float_of_int trade.quantity) rest
    in
    match accumulate 0 0. trades with
    | Error e -> Error e
    | Ok (0, _) -> Ok None
    | Ok (filled_lots, notional) ->
        let sign = match side with Book.Buy -> 1. | Book.Sell -> -1. in
        let vwap = notional /. float_of_int filled_lots in
        let slippage_ticks = sign *. (vwap -. arrival_mid) in
        let effective_spread_ticks = 2. *. slippage_ticks in
        let realized_spread_ticks = 2. *. sign *. (vwap -. later_mid) in
        let midpoint_impact_ticks = sign *. (later_mid -. arrival_mid) in
        if not (List.for_all Float.is_finite
                  [vwap; slippage_ticks; effective_spread_ticks; realized_spread_ticks; midpoint_impact_ticks]) then
          Error "impact arithmetic overflow"
        else Ok (Some { filled_lots; vwap; slippage_ticks; effective_spread_ticks
                       ; realized_spread_ticks; midpoint_impact_ticks })
