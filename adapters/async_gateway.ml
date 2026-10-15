open Async
let render_view ~base_revision view =
  let quote = match Reactive_quote.value view with
    | None -> "null"
    | Some (q : Analytics.quote) -> Printf.sprintf "{\"bid\":%d,\"ask\":%d,\"bid_quantity\":%d,\"ask_quantity\":%d,\"imbalance\":%.17g,\"microprice\":%.17g}"
        q.bid_price q.ask_price q.bid_quantity q.ask_quantity q.imbalance q.microprice in
  Printf.sprintf "{\"revision\":%d,\"quote\":%s}" (base_revision + Reactive_quote.revision view) quote
let serve ~reader ~writer initial =
  let view = Reactive_quote.create (Risk.book (Gateway.state initial)) in
  let base_revision = Gateway.quote_revision initial in
  let rec loop state =
    Deferred.bind (Reader.read_line reader) ~f:(function
      | `Eof -> Deferred.return state
      | `Ok line ->
        let state, response = Gateway.handle state line in
        Reactive_quote.set_book view (Risk.book (Gateway.state state));
        Reactive_quote.stabilize view;
        let response = if String.trim line = "quote" then render_view ~base_revision view else response in
        Writer.write_line writer response;
        Deferred.bind (Writer.flushed writer) ~f:(fun () -> loop state))
  in
  Monitor.protect (fun () -> loop initial)
    ~finally:(fun () -> Reactive_quote.close view; Deferred.unit)
