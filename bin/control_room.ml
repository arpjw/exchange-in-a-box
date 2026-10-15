open Async
let () =
  let count = ref 8 and batch = ref false in
  Arg.parse ["--accounts", Arg.Set_int count, "Account count (2..10000)";
             "--batch", Arg.Set batch, "Suppress banner and prompts for scripts"]
    (fun x -> raise (Arg.Bad ("unexpected argument: " ^ x)))
    "exchange-control-room [--accounts N] [--batch]";
  if !count < 2 || !count > 10000 then (prerr_endline "invalid account count"; Stdlib.exit 1);
  let limits : Risk.limits = { max_position=1000000; max_open_quantity=1000000; max_order_notional=1000000000000L } in
  match Gateway.create (List.init !count (fun id -> id, limits)) with
  | Error e -> prerr_endline e; Stdlib.exit 1
  | Ok gateway ->
    let surface = Control_surface.create gateway in
    let reader = Lazy.force Reader.stdin and writer = Lazy.force Writer.stdout in
    let write text = if text <> "" then Writer.write_line writer text in
    if not !batch then (write Control_surface.help; write (Control_surface.overview surface));
    let rec loop () =
      if not !batch then Writer.write writer "exchange> ";
      Deferred.bind (Writer.flushed writer) ~f:(fun () ->
        Deferred.bind (Reader.read_line reader) ~f:(function
          | `Eof -> Deferred.unit
          | `Ok line -> match Control_surface.command surface line with
            | Control_surface.Quit -> write "Session closed."; Writer.flushed writer
            | Control_surface.Output text -> write text; loop ()
            | Control_surface.Scenario config ->
              write (Printf.sprintf "SCENARIO starting seed=%d events=%d agents=%d impact_lots=%d (fresh sandbox)"
                       config.seed config.events config.agents config.impact_lots);
              Deferred.bind (Writer.flushed writer) ~f:(fun () ->
                Deferred.bind (In_thread.run (fun () -> Scenario.run config)) ~f:(fun result ->
                  (match result with
                   | Error e -> write ("SCENARIO error: " ^ e)
                   | Ok report -> write ("SCENARIO complete " ^ Scenario.summary config report));
                  loop ()))))
    in
    don't_wait_for (Deferred.bind
      (Monitor.protect loop ~finally:(fun () -> Control_surface.close surface; Writer.flushed writer))
      ~f:(fun () -> Shutdown.exit 0));
    Core.never_returns (Scheduler.go ())
