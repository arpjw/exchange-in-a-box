let () =
  let count = ref 8 in
  Arg.parse ["--accounts", Arg.Set_int count, "Number of accounts (2..10000)"]
    (fun x -> raise (Arg.Bad ("unexpected argument: " ^ x)))
    "exchange-worker: stdin line protocol, one JSON response per line";
  if !count < 2 || !count > 10000 then (prerr_endline "invalid account count"; exit 1);
  let limits : Risk.limits = { max_position = 1_000_000; max_open_quantity = 1_000_000; max_order_notional = 1_000_000_000_000L } in
  match Gateway.create (List.init !count (fun id -> id, limits)) with
  | Error e -> prerr_endline e; exit 1
  | Ok initial ->
    let rec loop state =
      match input_line stdin with
      | line -> let state, response = Gateway.handle state line in print_endline response; flush stdout; loop state
      | exception End_of_file -> ()
    in loop initial
