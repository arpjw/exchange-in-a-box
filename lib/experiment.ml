type regime = Passive | Active
type config =
  { seed : int; events : int; agents : int; initial_price : int
  ; shock_lots : int; regime : regime }
type pair =
  { seed : int; control_mid : float option; shocked_mid : float option
  ; midpoint_difference : float option
  ; shock_filled_lots : int; shock_cost_ticks_lots : int64
  ; innovation_digest : string }

let run_pair c =
  if c.events < 0 || c.events > 1_000_000 || c.agents < 2 || c.agents > 1000
     || c.initial_price < 100 || c.initial_price > 999_999_000
     || c.shock_lots < 0 || c.shock_lots > 2000 then Error "invalid experiment configuration"
  else
    let limits : Risk.limits = {max_position=1_000_000_000;max_open_quantity=1_000_000_000;
                               max_order_notional=1_000_000_000_000_000_000L} in
    match Risk.create (List.init (c.agents + 3) (fun id -> id, limits)) with
    | Error e -> Error e
    | Ok empty ->
        let failure = ref None in
        let execute state request =
          let next, _, trades = Risk.apply state request in
          (match Risk.check_invariants next with Ok () -> () | Error e -> failure := Some e);
          next, trades
        in
        let place state account id side price quantity policy =
          execute state (Risk.Place {account;id;side;price;quantity;policy}) in
        let initial = ref empty in
        for level = 1 to 20 do
          initial := fst (place !initial 0 (2*level) Book.Buy (c.initial_price-level) 100 Risk.Gtc);
          initial := fst (place !initial 1 (2*level+1) Book.Sell (c.initial_price+level) 100 Risk.Gtc)
        done;
        let control = ref !initial in
        let shocked, shock_fills = if c.shock_lots = 0 then !initial, [] else
          place !initial (c.agents+2) 42 Book.Buy (c.initial_price+20) c.shock_lots Risk.Ioc in
        let shocked = ref shocked in
        let rng = Random.State.make [|c.seed|] in
        let digest = ref "exchange-paired-innovations-v1" in
        for i = 0 to c.events - 1 do
          (* Consume all random innovations before consulting either arm. *)
          let account = 2 + Random.State.int rng c.agents in
          let buy = Random.State.bool rng in
          let maker_draw = Random.State.int rng 100 in
          let offset_draw = Random.State.int rng 11 - 5 in
          let quantity = 1 + Random.State.int rng 20 in
          let maker = maker_draw < (match c.regime with Passive -> 80 | Active -> 30) in
          let side = if buy then Book.Buy else Book.Sell in
          let offset = if maker then (if buy then -2 else 2) else offset_draw in
          digest := Digest.to_hex (Digest.string (Printf.sprintf "%s:%d:%b:%d:%d:%d"
            !digest account buy maker_draw offset_draw quantity));
          let apply_innovation state =
            let state = if i mod 5 = 0 then
              let state, _ = execute state (Risk.Halt account) in
              fst (execute state (Risk.Resume account)) else state in
            let center = match Analytics.quote (Risk.book state) with
              | None -> c.initial_price
              | Some q -> q.bid_price + q.spread / 2 in
            fst (place state account (100+i) side
              (max 1 (min 1_000_000_000 (center+offset))) quantity
              (if maker then Risk.Post_only else Risk.Ioc)) in
          control := apply_innovation !control;
          shocked := apply_innovation !shocked
        done;
        match !failure with Some e -> Error e | None ->
          let midpoint state = Option.map (fun (q : Analytics.quote) ->
            float_of_int q.bid_price +. float_of_int q.spread /. 2.)
            (Analytics.quote (Risk.book state)) in
          let control_mid = midpoint !control and shocked_mid = midpoint !shocked in
          let midpoint_difference = match control_mid, shocked_mid with
            | Some a, Some b -> Some (b -. a) | _ -> None in
          let shock_cost_ticks_lots = List.fold_left (fun cost (t : Book.trade) ->
            Int64.add cost (Int64.mul (Int64.of_int (t.price-c.initial_price))
              (Int64.of_int t.quantity))) 0L shock_fills in
          Ok {seed=c.seed;control_mid;shocked_mid;midpoint_difference;
              shock_filled_lots=Book.total_traded shock_fills;shock_cost_ticks_lots;
              innovation_digest= !digest}

type summary =
  { pairs : int; observed : int; missing : int; mean : float option
  ; sample_sd : float option; q025 : float option; median : float option
  ; q975 : float option; bootstrap_low : float option; bootstrap_high : float option }

let summarize ~bootstrap_seed ~resamples pairs =
  let seeds = List.map (fun (p : pair) -> p.seed) pairs in
  if resamples < 100 || resamples > 100000 then Error "bootstrap resamples must be in [100,100000]"
  else if List.length (List.sort_uniq Int.compare seeds) <> List.length seeds then Error "duplicate paired seeds"
  else
    let values = Array.of_list (List.filter_map (fun p -> p.midpoint_difference) pairs) in
    let n = Array.length values in
    if not (Array.for_all Float.is_finite values) then Error "nonfinite paired outcome"
    else
      let base = {pairs=List.length pairs;observed=n;missing=List.length pairs-n;mean=None;
                  sample_sd=None;q025=None;median=None;q975=None;bootstrap_low=None;bootstrap_high=None} in
      if n = 0 then Ok base
      else
        let mean = Array.fold_left ( +. ) 0. values /. float_of_int n in
        Array.sort Float.compare values;
        let quantile xs p =
          let index = p *. float_of_int (Array.length xs - 1) in
          let lo = int_of_float index in
          let hi = min (lo+1) (Array.length xs-1) in
          xs.(lo) +. (index -. float_of_int lo) *. (xs.(hi) -. xs.(lo)) in
        let base = {base with mean=Some mean;q025=Some (quantile values 0.025);
                             median=Some (quantile values 0.5);q975=Some (quantile values 0.975)} in
        if n = 1 then Ok base
        else
          let variance = Array.fold_left (fun acc x -> acc +. (x -. mean) ** 2.) 0. values
                         /. float_of_int (n-1) in
          let rng = Random.State.make [|bootstrap_seed|] in
          let means = Array.init resamples (fun _ ->
            let total = ref 0. in
            for _ = 1 to n do total := !total +. values.(Random.State.int rng n) done;
            !total /. float_of_int n) in
          Array.sort Float.compare means;
          Ok {base with sample_sd=Some (sqrt variance);bootstrap_low=Some (quantile means 0.025);
                        bootstrap_high=Some (quantile means 0.975)}
