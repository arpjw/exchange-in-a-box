let get = function Ok x -> x | Error e -> failwith e
let value = function None -> "" | Some x -> Printf.sprintf "%.8g" x
let () =
  print_endline "regime,shock_lots,seed,control_mid,shocked_mid,midpoint_difference,filled_lots,execution_cost_ticks_lots,innovation_digest";
  List.iter (fun (label,regime) ->
    List.iter (fun shock_lots ->
      let pairs = List.init 40 (fun index ->
        let seed = 1000+index in
        let pair = get (Experiment.run_pair
          Experiment.{seed;events=1000;agents=12;initial_price=10000;shock_lots;regime}) in
        Printf.printf "%s,%d,%d,%s,%s,%s,%d,%Ld,%s\n%!" label shock_lots seed
          (value pair.control_mid) (value pair.shocked_mid) (value pair.midpoint_difference)
          pair.shock_filled_lots pair.shock_cost_ticks_lots pair.innovation_digest;
        pair) in
      let summary = get (Experiment.summarize ~bootstrap_seed:20261014 ~resamples:5000 pairs) in
      Printf.eprintf "%s shock=%d n=%d missing=%d mean=%s sd=%s q025=%s median=%s q975=%s bootstrap95=[%s,%s]\n%!"
        label shock_lots summary.observed summary.missing (value summary.mean) (value summary.sample_sd)
        (value summary.q025) (value summary.median) (value summary.q975)
        (value summary.bootstrap_low) (value summary.bootstrap_high)) [0;200;800])
    ["passive",Experiment.Passive;"active",Experiment.Active]
