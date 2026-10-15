let unwrap = function Ok x -> x | Error e -> failwith e
let limits : Risk.limits = { max_position = 100; max_open_quantity = 100; max_order_notional = 10000L }
let fresh () = unwrap (Risk.create [0,limits; 1,limits; 2,limits])
let place account id side price quantity policy = Risk.Place { account; id; side; price; quantity; policy }
let ok t command = let t, status, trades = Risk.apply t command in assert (status = Risk.Accepted); unwrap (Risk.check_invariants t); t, trades
let reject t command reason = let next, status, trades = Risk.apply t command in assert (status = Risk.Rejected reason); assert (next = t); assert (trades = [])
let () =
  let t, _ = ok (fresh ()) (place 0 1 Book.Sell 100 10 Risk.Gtc) in
  reject t (place 1 2 Book.Buy 100 11 Risk.Fok) Risk.Cannot_fill;
  reject t (place 1 2 Book.Buy 100 5 Risk.Post_only) Risk.Would_cross;
  reject t (place 0 2 Book.Buy 100 5 Risk.Gtc) Risk.Self_trade;
  reject t (Risk.Cancel {account=1; id=1}) Risk.Unauthorized;
  let t, fills = ok t (place 1 2 Book.Buy 101 15 Risk.Ioc) in
  assert (Book.total_traded fills = 10 && Book.bids (Risk.book t) = [] && Book.asks (Risk.book t) = []);
  let a = List.find (fun (a : Risk.account) -> a.id = 1) (Risk.accounts t) in
  assert (a.position = 10 && a.cash = -1000L);
  reject t (place 1 2 Book.Buy 90 1 Risk.Gtc) (Risk.Engine Book.Duplicate_id);
  let t, _ = ok t (place 1 3 Book.Buy 90 90 Risk.Gtc) in
  reject t (place 1 4 Book.Buy 90 1 Risk.Gtc) Risk.Limit;
  let t, _ = ok t (Risk.Halt 1) in
  assert (Book.bids (Risk.book t) = []);
  reject t (place 1 5 Book.Buy 90 1 Risk.Gtc) Risk.Halted;
  let t, _ = ok t (Risk.Resume 1) in
  ignore (ok t (place 1 5 Book.Buy 90 1 Risk.Gtc));
  let t, _ = ok (fresh ()) (place 0 1 Book.Sell 100 10 Risk.Gtc) in
  let t, trades = ok t (place 1 2 Book.Buy 100 10 Risk.Fok) in
  assert (List.length trades = 1 && Book.asks (Risk.book t) = []);
  reject (fresh ()) (place 0 1 Book.Buy 1000 11 Risk.Gtc) Risk.Limit;
  reject (fresh ()) (place 8 1 Book.Buy 100 1 Risk.Gtc) Risk.Unknown_account;
  for seed = 0 to 19 do
    let config : Scenario.config = { seed; events = 1000; agents = 8; initial_price = 10000; impact_lots = 250 } in
    let a = unwrap (Scenario.run config) and b = unwrap (Scenario.run config) in
    assert (Scenario.summary config a = Scenario.summary config b);
    assert (Risk.accounts a.state = Risk.accounts b.state);
    assert (a.impact_cost = 450L);
    unwrap (Risk.check_invariants a.state)
  done;
  print_endline "runtime: risk policies, accounting, kill switch and 40 seeded scenario runs passed"

let () =
  let initial = unwrap (Gateway.create [0,limits; 1,limits]) in
  let a, _ = Gateway.handle initial "place 0 1 buy 99 10 gtc" in
  assert (Gateway.quote_revision a = 0);
  let b, _ = Gateway.handle a "place 1 2 sell 101 10 gtc" in
  assert (Gateway.quote_revision b = 1);
  let c, _ = Gateway.handle b "place 1 3 sell 105 10 gtc" in
  assert (Gateway.quote_revision c = 1);
  let d, _ = Gateway.handle c "cancel 1 2" in
  assert (Gateway.quote_revision d = 2);
  let e, response = Gateway.handle d "place 0 nope buy 99 10 gtc" in
  assert (e = d && response = "{\"status\":\"error\",\"reason\":\"invalid_command\"}");
  let f, _ = Gateway.handle e "halt 0" in
  assert (Gateway.quote_revision f = 3);
  unwrap (Risk.check_invariants (Gateway.state f));
  print_endline "gateway: cached quote revisions and malformed command isolation passed"

let () =
  for seed = 0 to 9 do
    let rng = Random.State.make [| seed; 81 |] and state = ref (fresh ()) in
    for id = 0 to 4999 do
      let account = Random.State.int rng 3 in
      let policy = [|Risk.Gtc; Risk.Ioc; Risk.Fok; Risk.Post_only|].(Random.State.int rng 4) in
      let request = match Random.State.int rng 12 with
        | 0 -> Risk.Halt account
        | 1 -> Risk.Resume account
        | 2 -> Risk.Cancel {account; id=Random.State.int rng (id + 1)}
        | _ -> place account id (if Random.State.bool rng then Book.Buy else Book.Sell)
                 (95 + Random.State.int rng 11) (1 + Random.State.int rng 120) policy in
      let next, status, trades = Risk.apply !state request in
      (match status with Risk.Rejected _ -> assert (next = !state && trades = []) | Risk.Accepted -> ());
      unwrap (Risk.check_invariants next);
      state := next
    done;
    for account = 0 to 2 do let next, _ = ok !state (Risk.Halt account) in state := next done;
    assert (Book.bids (Risk.book !state) = [] && Book.asks (Risk.book !state) = [])
  done;
  print_endline "risk stress: 50000 random requests passed invariant and rejection atomicity checks"
