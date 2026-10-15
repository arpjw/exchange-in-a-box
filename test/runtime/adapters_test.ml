let apply book command = let b, status, _ = Book.apply book command in assert (status = Book.Accepted); b
let buy id price = Book.Submit { id; side=Book.Buy; price; quantity=10 }
let sell id price = Book.Submit { id; side=Book.Sell; price; quantity=10 }
let () =
  let view = Reactive_quote.create Book.empty in
  assert (Reactive_quote.value view = None && Reactive_quote.revision view = 0);
  let b = apply Book.empty (buy 1 99) |> fun b -> apply b (sell 2 101) in
  Reactive_quote.set_book view b;
  Reactive_quote.stabilize view;
  assert (Reactive_quote.value view = Analytics.quote b && Reactive_quote.revision view = 1);
  let deep = apply b (sell 3 110) in
  Reactive_quote.set_book view deep;
  Reactive_quote.stabilize view;
  assert (Reactive_quote.revision view = 1);
  let changed = apply deep (Book.Cancel 2) in
  Reactive_quote.set_book view changed;
  Reactive_quote.set_book view deep;
  Reactive_quote.stabilize view;
  assert (Reactive_quote.revision view = 1);
  Reactive_quote.set_book view changed;
  Reactive_quote.stabilize view;
  assert (Reactive_quote.revision view = 2 && Reactive_quote.value view = Analytics.quote changed);
  let independent = Reactive_quote.create Book.empty in
  assert (Reactive_quote.value independent = None);
  Reactive_quote.close independent;
  Reactive_quote.close view;
  Reactive_quote.close view;
  assert (try ignore (Reactive_quote.value view); false with Invalid_argument _ -> true);
  print_endline "Incremental: quote propagation, cutoff, batched updates and observer lifecycle passed"
