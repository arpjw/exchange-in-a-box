(* Reproducible, synthetic model-recovery diagnostic. Printed likelihoods refer
   only to generated event streams and imply no empirical market validation. *)
let get = function Ok x -> x | Error e -> failwith e
let () =
  print_endline "generator,seed,events,poisson_heldout,hawkes_heldout,baseline,branching_ratio,decay,residual_mean,residual_ks";
  List.iter (fun (label, parameters) ->
    for seed = 100 to 109 do
      let times = get (Research.simulate_hawkes ~seed ~max_events:200000
        ~max_candidates:400000 ~horizon:10000. parameters) in
      let result = get (Research.compare ~split:7000. ~horizon:10000.
        ~decays:[0.3;0.6;1.2;2.4] ~branching_ratios:[0.;0.25;0.5;0.75]
        ~baseline_multipliers:[0.25;0.5;0.75;1.] times) in
      let p = result.hawkes.parameters in
      let optional = function None -> "" | Some x -> Printf.sprintf "%.8g" x in
      Printf.printf "%s,%d,%d,%.10g,%.10g,%.8g,%.8g,%.8g,%s,%s\n%!"
        label seed (List.length times) result.poisson.heldout_log_likelihood
        result.hawkes.heldout_log_likelihood p.baseline
        (Analytics.Hawkes.branching_ratio p) p.decay
        (optional result.hawkes.residual_mean) (optional result.hawkes.residual_ks)
    done)
    ["poisson", Analytics.Hawkes.{baseline=4.;excitation=0.;decay=1.2};
     "hawkes", Analytics.Hawkes.{baseline=2.;excitation=0.6;decay=1.2}];
  let large = get (Research.simulate_hawkes ~seed:20261014 ~max_events:1200000
    ~max_candidates:1300000 ~horizon:1000000.
    Analytics.Hawkes.{baseline=1.;excitation=0.;decay=1.}) in
  let ll = get (Research.conditional_log_likelihood
    Analytics.Hawkes.{baseline=1.;excitation=0.;decay=1.}
    ~start:500000. ~horizon:1000000. large) in
  if ll <> -500000. then failwith "million-event Poisson exact likelihood";
  Printf.eprintf "stress passed: %d-event path, exact held-out log likelihood %.1f\n" (List.length large) ll
