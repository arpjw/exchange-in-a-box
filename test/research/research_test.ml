let get = function Ok x -> x | Error e -> failwith e
let check b s = if not b then failwith s
let near x y = abs_float (x -. y) < 1e-8 *. max 1. (abs_float y)
let p = Analytics.Hawkes.{baseline=2.; excitation=0.6; decay=1.2}
let simulate seed = get (Research.simulate_hawkes ~seed ~max_events:100000 ~max_candidates:200000 ~horizon:1000. p)
let compare times = get (Research.compare ~split:700. ~horizon:1000.
  ~decays:[0.6;1.2;2.4] ~branching_ratios:[0.;0.25;0.5;0.75]
  ~baseline_multipliers:[0.25;0.5;0.75;1.] times)

let () =
  let times = simulate 42 in
  check (times = simulate 42) "seed reproducibility";
  check (times <> simulate 43) "different seeds";
  let result = compare times in
  check (result.hawkes.training_log_likelihood >= result.poisson.training_log_likelihood -. 1e-8)
    "grid includes Poisson MLE";
  let extra = List.filter (fun t -> t <= 700.) times @ [701.;702.;999.] in
  let other = compare extra in
  check (result.hawkes.parameters = other.hawkes.parameters) "held-out leakage into fit";
  check (result.hawkes.residual_count = result.heldout_events - 1) "residual split interval exclusion";
  let full = get (Analytics.Hawkes.log_likelihood p ~horizon:1000. times) in
  let train = get (Analytics.Hawkes.log_likelihood p ~horizon:700. (List.filter (fun t -> t <= 700.) times)) in
  let test = get (Research.conditional_log_likelihood p ~start:700. ~horizon:1000. times) in
  check (near (full -. train) test) "conditional likelihood decomposition";
  let boundary = get (Research.conditional_log_likelihood p ~start:1. ~horizon:2. [0.5;1.;1.5]) in
  let full = get (Analytics.Hawkes.log_likelihood p ~horizon:2. [0.5;1.;1.5]) in
  let train = get (Analytics.Hawkes.log_likelihood p ~horizon:1. [0.5;1.]) in
  check (near boundary (full -. train)) "split boundary history";
  List.iter (fun decay ->
    let edge = Analytics.Hawkes.{baseline=2.; excitation=0.5 *. decay; decay} in
    let ll = get (Research.conditional_log_likelihood edge ~start:1. ~horizon:2. [0.5;1.;1.5]) in
    check (Float.is_finite ll) "extreme decay likelihood") [1e-200;1e200];
  let poisson = Analytics.Hawkes.{baseline=2.; excitation=0.; decay=1.} in
  let pll = get (Research.conditional_log_likelihood poisson ~start:1. ~horizon:2. [0.2;0.5;1.5]) in
  check (near pll (log 2. -. 2.)) "zero excitation Poisson limit";
  check (Result.is_error (Research.simulate_hawkes ~seed:1 ~max_events:100 ~max_candidates:200 ~horizon:2.
    Analytics.Hawkes.{baseline=2.;excitation=1.;decay=1.})) "stationarity boundary";
  let empty = compare [] in
  check (empty.poisson.training_log_likelihood = 0. && empty.poisson.heldout_log_likelihood = 0.) "empty Poisson";
  check ((compare [900.]).poisson.heldout_log_likelihood = neg_infinity) "zero-rate prediction";
  check (Result.is_error (Research.simulate_hawkes ~seed:1 ~max_events:0 ~max_candidates:100 ~horizon:1000. p)) "event bound";
  check (Result.is_error (Research.simulate_hawkes ~seed:1 ~max_events:100000 ~max_candidates:1 ~horizon:1000. p)) "candidate bound";
  check (Result.is_error (Research.compare ~split:1. ~horizon:2. ~decays:[1.] ~branching_ratios:[1.] ~baseline_multipliers:[1.] [])) "invalid ratio";
  check (Result.is_error (Research.conditional_log_likelihood p ~start:1. ~horizon:2. [1.;1.])) "duplicate time";
  let trades = Book.[{maker_id=1;taker_id=3;price=101;quantity=2};{maker_id=2;taker_id=3;price=104;quantity=1}] in
  let m = match get (Research.impact ~side:Book.Buy ~arrival_mid:100. ~later_mid:101. trades) with Some x -> x | None -> failwith "impact" in
  check (m.filled_lots = 3 && near m.vwap 102.) "VWAP";
  check (near m.effective_spread_ticks (m.realized_spread_ticks +. 2. *. m.midpoint_impact_ticks)) "spread decomposition";
  let s = match get (Research.impact ~side:Book.Sell ~arrival_mid:100. ~later_mid:101. trades) with Some x -> x | None -> failwith "impact" in
  check (near s.slippage_ticks (-.m.slippage_ticks)) "sell sign";
  check (get (Research.impact ~side:Book.Buy ~arrival_mid:100. ~later_mid:101. []) = None) "no fills";
  (* Repeated independent paths test the sampler's finite-horizon first moment.
     E[N(T)] = mu*T/(1-r) - mu*r*(1-exp(-(beta-alpha)*T))/((1-r)*(beta-alpha)). *)
  let samples = 80 and horizon = 100. in
  let total = ref 0 in
  for seed = 1 to samples do
    let path = get (Research.simulate_hawkes ~seed ~max_events:10000 ~max_candidates:20000 ~horizon p) in
    total := !total + List.length path
  done;
  let r = p.excitation /. p.decay in
  let expected = p.baseline *. horizon /. (1. -. r)
    -. p.baseline *. r *. (-.expm1 (-.(p.decay -. p.excitation) *. horizon))
       /. ((1. -. r) *. (p.decay -. p.excitation)) in
  check (abs_float (float_of_int !total /. float_of_int samples -. expected) < 0.08 *. expected)
    "multi-seed Hawkes first moment";
  Printf.printf "research tests passed: %d seeded paths, %d events; fit grid=%d\n" samples !total result.hawkes_candidates
