open Analytics

let near a b = abs_float (a -. b) < 1e-10
let expect condition message = if not condition then failwith message

let test_quote () =
  let open Book in
  let commands =
    [ Submit { id = 1; side = Buy; price = 99; quantity = 6 }
    ; Submit { id = 2; side = Buy; price = 99; quantity = 4 }
    ; Submit { id = 3; side = Sell; price = 101; quantity = 5 }
    ]
  in
  let book, _ = replay commands in
  match quote book with
  | None -> failwith "missing two-sided quote"
  | Some q ->
      expect (q.bid_quantity = 10 && q.ask_quantity = 5 && q.spread = 2)
        "quote size or spread failed";
      expect (near q.imbalance (1. /. 3.)) "imbalance failed";
      expect (near q.microprice (100. +. 1. /. 3.)) "microprice failed"

let test_hawkes () =
  let p = Hawkes.{ baseline = 2.; excitation = 0.4; decay = 1. } in
  let likelihood =
    match Hawkes.log_likelihood p ~horizon:1. [ 0.; 0.5 ] with
    | Ok x -> x | Error message -> failwith message
  in
  let expected =
    log 2. +. log (2. +. 0.4 *. exp (-0.5)) -. 2.
    -. 0.4 *. (1. -. exp (-1.) +. 1. -. exp (-0.5))
  in
  expect (near likelihood expected) "Hawkes likelihood disagrees with direct formula";
  let residuals =
    match Hawkes.compensator_increments p [ 0.5; 1. ] with
    | Ok x -> x | Error message -> failwith message
  in
  expect (List.length residuals = 2) "wrong compensator length";
  expect (near (List.hd residuals) 1.) "first compensator increment failed";
  expect
    (match Hawkes.log_likelihood p ~horizon:1. [ 0.5; 0.5 ] with
     | Error _ -> true | Ok _ -> false)
    "duplicate event time accepted"

let () =
  test_quote ();
  test_hawkes ();
  print_endline "analytics tests passed"
