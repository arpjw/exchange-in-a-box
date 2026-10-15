let () =
  let seed = ref 42 and events = ref 10000 and agents = ref 20 and price = ref 10000 and impact = ref 0 in
  Arg.parse
    [ "--seed", Arg.Set_int seed, "Deterministic random seed"
    ; "--events", Arg.Set_int events, "Synthetic events (0..10000000)"
    ; "--agents", Arg.Set_int agents, "Synthetic agents (2..10000)"
    ; "--price", Arg.Set_int price, "Initial reference price in ticks"
    ; "--impact-lots", Arg.Set_int impact, "Initial IOC buy intervention in lots"
    ] (fun x -> raise (Arg.Bad ("unexpected argument: " ^ x)))
    "exchange-scenario [options]: synthetic simulation, JSON output";
  let config : Scenario.config = { seed = !seed; events = !events; agents = !agents; initial_price = !price; impact_lots = !impact } in
  match Scenario.run config with
  | Error e -> prerr_endline e; exit 1
  | Ok r -> print_endline (Scenario.summary config r)
