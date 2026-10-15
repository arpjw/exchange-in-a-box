let () =
  let count = ref 8 in
  Arg.parse ["--accounts", Arg.Set_int count, "Number of accounts (2..10000)"]
    (fun x -> raise (Arg.Bad ("unexpected argument: " ^ x)))
    "exchange-async-worker: Async stdin/JSON and Incremental quotes";
  if !count < 2 || !count > 10000 then (prerr_endline "invalid account count"; exit 1);
  let limits : Risk.limits = { max_position = 1_000_000; max_open_quantity = 1_000_000; max_order_notional = 1_000_000_000_000L } in
  match Gateway.create (List.init !count (fun id -> id, limits)) with
  | Error e -> prerr_endline e; exit 1
  | Ok initial ->
    Async.don't_wait_for
      (Async.Deferred.bind
         (Async_gateway.serve ~reader:(Lazy.force Async.Reader.stdin) ~writer:(Lazy.force Async.Writer.stdout) initial)
         ~f:(fun _ -> Async.Shutdown.exit 0));
    Core.never_returns (Async.Scheduler.go ())
