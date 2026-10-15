open Book

let submit id side price quantity = Submit { id; side; price; quantity }

let expect condition message = if not condition then failwith message

let check book =
  match check_invariants book with Ok () -> () | Error message -> failwith message

let test_fifo_and_partial_fill () =
  let commands =
    [ submit 1 Sell 101 5; submit 2 Sell 101 3; submit 3 Buy 102 7 ]
  in
  let book, results = replay commands in
  let trades = match List.nth results 2 with _, trades -> trades in
  expect (trades =
          [ { maker_id = 1; taker_id = 3; price = 101; quantity = 5 }
          ; { maker_id = 2; taker_id = 3; price = 101; quantity = 2 }
          ]) "FIFO matching or resting-price execution failed";
  expect (List.map (fun o -> o.id, o.quantity) (asks book) = [ 2, 1 ])
    "partial maker quantity is wrong";
  check book

let test_cancel_and_reject () =
  let book, _, _ = apply empty (submit 8 Buy 99 4) in
  let book, status, _ = apply book (Cancel 8) in
  expect (status = Accepted && bids book = []) "cancel failed";
  let book2, status, _ = apply book (submit 8 Buy 99 4) in
  expect (book2 = book && status = Rejected Duplicate_id) "id reuse accepted";
  let book2, status, _ = apply book (Cancel 999) in
  expect (book2 = book && status = Rejected Unknown_id) "unknown cancel accepted";
  check book

let test_replay_and_fuzz () =
  let state = Random.State.make [| 2026; 10; 14 |] in
  let commands =
    List.init 2_000 (fun id ->
      if id mod 7 = 0 then Cancel (Random.State.int state (id + 1))
      else
        submit id (if Random.State.bool state then Buy else Sell)
          (90 + Random.State.int state 21) (1 + Random.State.int state 20))
  in
  let book, results = replay commands in
  let replayed, results2 = replay commands in
  expect (book = replayed && results = results2) "replay is not deterministic";
  let _ =
    List.fold_left
      (fun book command ->
        let book, _, trades = apply book command in
        check book;
        expect (List.for_all (fun trade -> trade.quantity > 0) trades)
          "non-positive trade";
        (match command with
         | Submit { id; quantity; _ } when List.exists (fun trade -> trade.taker_id = id) trades ->
             let resting =
               List.fold_left
                 (fun total order -> if order.id = id then total + order.quantity else total)
                 0 (bids book @ asks book)
             in
             expect (total_traded trades + resting = quantity)
               "incoming quantity was not conserved"
         | _ -> ());
        book)
      empty commands
  in
  check book

let () =
  test_fifo_and_partial_fill ();
  test_cancel_and_reject ();
  test_replay_and_fuzz ();
  print_endline "book tests passed"
