module Incr = Incremental.Make ()
type t = { input : Book.t Incr.Var.t; output : Analytics.quote option Incr.Observer.t; changes : int ref; mutable closed : bool }
let check t = if t.closed then invalid_arg "Reactive_quote: closed observer"
let create book =
  let input = Incr.Var.create book in
  let quote = Incr.map (Incr.Var.watch input) ~f:Analytics.quote in
  Incr.set_cutoff quote (Incr.Cutoff.of_equal ( = ));
  let output = Incr.observe quote and changes = ref 0 in
  Incr.Observer.on_update_exn output ~f:(function
    | Incr.Observer.Update.Changed _ -> incr changes
    | Incr.Observer.Update.Initialized _ | Incr.Observer.Update.Invalidated -> ());
  Incr.stabilize ();
  { input; output; changes; closed = false }
let set_book t book = check t; Incr.Var.set t.input book
let stabilize t = check t; Incr.stabilize ()
let value t = check t; Incr.Observer.value_exn t.output
let revision t = check t; !(t.changes)
let close t = if not t.closed then begin Incr.Observer.disallow_future_use t.output; t.closed <- true; Incr.stabilize () end
