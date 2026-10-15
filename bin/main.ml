open Book

let show_side = function Buy -> "buy" | Sell -> "sell"

let show_order order =
  Printf.sprintf "#%d %s %d @ %d (seq %d)" order.id
    (show_side order.side) order.quantity order.price order.sequence

let sample =
  [ Submit { id = 1; side = Sell; price = 101; quantity = 5 }
  ; Submit { id = 2; side = Sell; price = 101; quantity = 3 }
  ; Submit { id = 3; side = Buy; price = 102; quantity = 7 }
  ; Submit { id = 4; side = Buy; price = 100; quantity = 4 }
  ]

let () =
  let book, results = replay sample in
  List.iteri
    (fun index (status, trades) ->
      let status = match status with Accepted -> "accepted" | Rejected _ -> "rejected" in
      Printf.printf "event %d: %s\n" (index + 1) status;
      List.iter
        (fun trade ->
          Printf.printf "  fill maker=%d taker=%d qty=%d price=%d\n"
            trade.maker_id trade.taker_id trade.quantity trade.price)
        trades)
    results;
  Printf.printf "bids:\n";
  List.iter (fun order -> Printf.printf "  %s\n" (show_order order)) (bids book);
  Printf.printf "asks:\n";
  List.iter (fun order -> Printf.printf "  %s\n" (show_order order)) (asks book)
