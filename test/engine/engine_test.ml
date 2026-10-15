let expect b s = if not b then failwith s
let ok = function Ok x -> x | Error s -> failwith s
let event ?(timestamp=0L) ?(venue="X") ?(instrument="ABC") id side price quantity =
  { Engine.timestamp; venue; instrument; command = Book.Submit { id; side; price; quantity } }
let test_routes () =
  let events = [event 1 Sell 100 4; event ~venue:"Y" 1 Buy 101 2; event ~instrument:"DEF" 1 Buy 101 2; event ~timestamp:1L 2 Buy 101 3] in
  let state, outcomes = Engine.replay events in
  expect (List.nth outcomes 3 = Engine.Applied (Book.Accepted, [{Book.maker_id=1;taker_id=2;price=100;quantity=3}])) "route matching";
  expect (List.length (Book.bids (Engine.book state ~venue:"Y" ~instrument:"ABC")) = 1) "venue isolation";
  let unchanged, out = Engine.apply state (event 3 Buy 100 1) in
  expect (state = unchanged && out = Engine.Time_regression) "clock regression mutated state";
  let unchanged, out = Engine.apply state (event ~venue:"bad\nroute" 3 Buy 100 1) in
  expect (state = unchanged && out = Engine.Invalid_route) "invalid route mutated state";
  ignore (ok (Engine.check_invariants state));
  expect (Engine.replay events = (state, outcomes)) "engine replay"
let test_schedule () =
  let events = List.init 5 (fun id -> event ~timestamp:(Int64.of_int id) id Buy 99 1) in
  let schedule () = ok (Engine.schedule ~latency:(fun i -> if i = 0 then 3L else 0L) ~drop:(fun i -> i = 2) events) in
  let scheduled = schedule () in
  let ids = List.map (fun e -> match e.Engine.command with Book.Submit {id;_}->id | _ -> -1) scheduled in
  expect (ids = [1;0;3;4]) "latency ordering, stable ties, or drop failed";
  expect (scheduled = schedule ()) "schedule nondeterministic";
  expect (Result.is_error (Engine.schedule ~latency:(fun _ -> 1L) ~drop:(fun _ -> false) [event ~timestamp:Int64.max_int 0 Buy 1 1])) "overflow accepted";
  expect (Result.is_error (Engine.schedule ~latency:(fun _ -> -1L) ~drop:(fun _ -> false) events)) "negative latency accepted"
let with_path f =
  let path = Filename.temp_file "exchange-journal" ".log" in
  Sys.remove path;
  Fun.protect ~finally:(fun () -> if Sys.file_exists path then Sys.remove path) (fun () -> f path)
let add_bytes path s = let oc = open_out_gen [Open_wronly;Open_append;Open_binary] 0o600 path in output_string oc s; close_out oc
let test_journal () = with_path (fun path ->
  let events = [event 1 Sell 100 4;event ~timestamp:1L 2 Buy 101 3;event ~timestamp:2L 2 Buy 101 3] in
  List.iter (fun e -> ignore (ok (Journal.append path e))) events;
  let recovered = ok (Journal.recover path) in
  expect (recovered.events = events && not recovered.ignored_tail) "journal roundtrip";
  expect ((recovered.state, recovered.outcomes) = Engine.replay events) "journal replay";
  add_bytes path "3\t2\tX";
  expect ((ok (Journal.recover path)).ignored_tail) "incomplete tail not identified";
  expect (Result.is_error (Journal.append path (List.hd events))) "append accepted incomplete tail";
  expect (ok (Journal.repair_tail path)) "tail repair failed";
  expect (not (ok (Journal.repair_tail path))) "repair not idempotent";
  ignore (ok (Journal.append path (event ~timestamp:3L 4 Buy 100 1)));
  expect (List.length (ok (Journal.recover path)).events = 4) "append after repair";
  add_bytes path "4\tgarbage\n";
  expect (Result.is_error (Journal.recover path)) "complete corrupt record accepted";
  expect (Result.is_error (Journal.repair_tail path)) "repair erased corrupt complete record")
let test_corruption () = with_path (fun path ->
  ignore (ok (Journal.append path (event 1 Buy 100 1)));
  let ic = open_in_bin path in let data = really_input_string ic (in_channel_length ic) in close_in ic;
  let bytes = Bytes.of_string data in Bytes.set bytes (String.length data - 4) 'z';
  let oc = open_out_bin path in output_bytes oc bytes; close_out oc;
  expect (Result.is_error (Journal.recover path)) "checksum corruption accepted")
let test_every_truncated_tail () = with_path (fun path ->
  let first = event 1 Sell 100 4 and second = event ~timestamp:1L 2 Buy 101 3 in
  ignore (ok (Journal.append path first));
  let ic = open_in_bin path in let prefix_length = in_channel_length ic in close_in ic;
  ignore (ok (Journal.append path second));
  let ic = open_in_bin path in let data = really_input_string ic (in_channel_length ic) in close_in ic;
  for length = prefix_length to String.length data - 1 do
    let oc = open_out_bin path in output_substring oc data 0 length; close_out oc;
    let recovered = ok (Journal.recover path) in
    expect (recovered.events = [first]) "truncated tail changed valid prefix";
    expect (recovered.ignored_tail = (length > prefix_length)) "tail classification";
    ignore (ok (Journal.repair_tail path));
    ignore (ok (Journal.append path second));
    expect ((ok (Journal.recover path)).events = [first;second]) "repaired journal restart differed"
  done)
let test_deep_book () =
  let count = 50_000 in
  let book = ref Book.empty in
  for id = 1 to count do
    let next, status, _ = Book.apply !book (Book.Submit {id;side=Buy;price=id;quantity=1}) in
    expect (status = Book.Accepted) "deep book insert";
    book := next
  done;
  let next, status, _ = Book.apply !book (Book.Submit {id=count+1;side=Buy;price=1;quantity=1}) in
  expect (status = Book.Accepted) "deep FIFO insert";
  let next, status, _ = Book.apply next (Book.Cancel (count+1)) in
  expect (status = Book.Accepted) "deep cancellation";
  let next, status, trades = Book.apply next (Book.Submit {id=count+2;side=Sell;price=1;quantity=count}) in
  expect (status = Book.Accepted && Book.bids next = [] && Book.total_traded trades = count) "deep sweep conservation";
  ignore (ok (Book.check_invariants next));
  Printf.printf "deep book stress passed: %d resting orders swept\n" count
let test_persistent_stress () = with_path (fun path ->
  let count = 60_000 in
  let events = List.init count (fun id -> event ~timestamp:(Int64.of_int id) id (if id mod 2 = 0 then Book.Buy else Book.Sell) 100 (1 + id mod 7)) in
  let writer, recovery = ok (Journal.open_writer path) in
  expect (recovery.events = []) "new writer is nonempty";
  expect (Result.is_error (Journal.append_writer writer (event ~venue:"bad\nvenue" 1 Buy 100 1))) "writer accepted delimiter";
  List.iteri (fun i e ->
    ignore (ok (Journal.append_writer writer e));
    if i mod 10_000 = 0 then ignore (ok (Journal.flush_writer writer))) events;
  ignore (ok (Journal.flush_writer writer));
  ignore (ok (Journal.close_writer writer));
  ignore (ok (Journal.close_writer writer));
  expect (Result.is_error (Journal.append_writer writer (List.hd events))) "closed writer accepted event";
  expect (Result.is_error (Journal.flush_writer writer)) "closed writer accepted flush";
  let expected_state, expected_outcomes = Engine.replay events in
  let writer, recovery = ok (Journal.open_writer path) in
  expect (recovery.events = events && recovery.state = expected_state && recovery.outcomes = expected_outcomes) "persistent stress replay mismatch";
  let last = event ~timestamp:(Int64.of_int count) count Buy 100 1 in
  ignore (ok (Journal.append_writer writer last));
  ignore (ok (Journal.close_writer writer));
  let recovery = ok (Journal.recover path) in
  expect (List.length recovery.events = count + 1 && List.nth recovery.events count = last) "writer reopen lost sequence";
  add_bytes path "partial";
  expect (Result.is_error (Journal.open_writer path)) "writer accepted partial tail";
  ignore (ok (Journal.repair_tail path));
  let writer, recovery = ok (Journal.open_writer path) in
  expect (List.length recovery.events = count + 1) "writer repair lost records";
  ignore (ok (Journal.close_writer writer));
  add_bytes path "bad complete record\n";
  expect (Result.is_error (Journal.open_writer path)) "writer accepted corrupt complete record";
  Printf.printf "persistent journal stress passed: %d records, flush/reopen/recovery\n" (count+1))
let test_stress () =
  let seeds = 12 and count = 10_000 in
  for seed = 0 to seeds - 1 do
    let rng = Random.State.make [|seed;314159|] in
    let state = ref Engine.empty in
    let accepted = ref 0L and cancelled = ref 0L and traded = ref 0L in
    for id = 0 to count - 1 do
      let venue = if id mod 2 = 0 then "X" else "Y" in
      let instrument = if id mod 3 = 0 then "ABC" else "DEF" in
      let before = Engine.book !state ~venue ~instrument in
      let command = if id mod 5 = 0 then Book.Cancel (Random.State.int rng (id + 1)) else Book.Submit {id;side=(if Random.State.bool rng then Buy else Sell);price=90 + Random.State.int rng 21;quantity=1 + Random.State.int rng 100} in
      let prior_quantity = match command with Book.Cancel cid -> List.fold_left (fun n (o:Book.order)->if o.id=cid then n+o.quantity else n) 0 (Book.bids before @ Book.asks before) | _ -> 0 in
      let next, outcome = Engine.apply !state {Engine.timestamp=Int64.of_int id;venue;instrument;command} in
      state := next;
      (match outcome with
       | Engine.Applied (Book.Accepted, ts) ->
           (match command with Book.Submit {quantity;_} -> accepted := Int64.add !accepted (Int64.of_int quantity) | Book.Cancel _ -> cancelled := Int64.add !cancelled (Int64.of_int prior_quantity));
           traded := Int64.add !traded (Int64.of_int (Book.total_traded ts))
       | _ -> ());
      if id mod 100 = 0 then ignore (ok (Engine.check_invariants !state))
    done;
    let resting = List.fold_left (fun total (venue,instrument) -> let b = Engine.book !state ~venue ~instrument in List.fold_left (fun n (o:Book.order) -> Int64.add n (Int64.of_int o.quantity)) total (Book.bids b @ Book.asks b)) 0L ["X","ABC";"X","DEF";"Y","ABC";"Y","DEF"] in
    expect (!accepted = Int64.add resting (Int64.add !cancelled (Int64.mul 2L !traded))) "global submitted = resting + cancelled + twice traded conservation";
    ignore (ok (Engine.check_invariants !state))
  done;
  Printf.printf "engine stress passed: %d seeds, %d total events\n" seeds (seeds * count)
let () = test_routes (); test_schedule (); test_journal (); test_corruption (); test_every_truncated_tail (); test_stress (); test_deep_book (); test_persistent_stress (); print_endline "engine/journal tests passed"
