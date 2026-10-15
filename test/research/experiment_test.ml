let get = function Ok x -> x | Error e -> failwith e
let check b s = if not b then failwith s
let config : Experiment.config = {seed=17;events=500;agents=12;initial_price=10000;shock_lots=400;regime=Passive}
let () =
  let zero = get (Experiment.run_pair {config with shock_lots=0}) in
  check (zero.midpoint_difference=Some 0. && zero.shock_cost_ticks_lots=0L) "zero intervention identity";
  let shock = get (Experiment.run_pair config) in
  check (shock=get (Experiment.run_pair config)) "exact paired replay";
  check (zero.innovation_digest=shock.innovation_digest) "identical innovations across intervention sizes";
  let initial = get (Experiment.run_pair {config with events=0;shock_lots=250}) in
  check (initial.shock_filled_lots=250 && initial.shock_cost_ticks_lots=450L) "ladder execution cost";
  check (initial.midpoint_difference=Some 1.) "immediate midpoint shift";
  let samples = List.init 30 (fun seed -> get (Experiment.run_pair {config with seed})) in
  let summary = get (Experiment.summarize ~bootstrap_seed:7 ~resamples:2000 samples) in
  check (summary.observed+summary.missing=30) "missing outcome accounting";
  check (summary=get (Experiment.summarize ~bootstrap_seed:7 ~resamples:2000 (List.rev samples))) "order-independent bootstrap";
  check (Result.is_error (Experiment.summarize ~bootstrap_seed:7 ~resamples:2000 [shock;shock])) "duplicate seed rejection";
  let absent = {shock with midpoint_difference=None;control_mid=None} in
  let missing = get (Experiment.summarize ~bootstrap_seed:7 ~resamples:2000 [absent]) in
  check (missing.observed=0 && missing.missing=1 && missing.mean=None && missing.bootstrap_low=None) "missing not zero imputed";
  let constant = List.init 10 (fun seed -> {shock with seed;midpoint_difference=Some 3.}) in
  let fixed = get (Experiment.summarize ~bootstrap_seed:7 ~resamples:2000 constant) in
  check (fixed.mean=Some 3. && fixed.sample_sd=Some 0. && fixed.bootstrap_low=Some 3. && fixed.bootstrap_high=Some 3.) "constant bootstrap";
  Printf.printf "paired experiment passed: 30 seeds, 30000 population arm events; observed=%d missing=%d\n" summary.observed summary.missing
