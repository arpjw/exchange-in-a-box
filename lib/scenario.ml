type config = { seed : int; events : int; agents : int; initial_price : int; impact_lots : int }
type report = { accepted : int; rejected : int; fills : int; volume : int; final_mid : float option; impact_cost : int64; state : Risk.t }
let run_with ~sample c =
  if c.events < 0 || c.events > 10_000_000 || c.agents < 2 || c.agents > 10_000
     || c.initial_price < 100 || c.initial_price > 999_999_000 || c.impact_lots < 0 || c.impact_lots > 1_000_000 then
    Error "invalid scenario configuration" else
  let limits : Risk.limits = { max_position = 1_000_000_000; max_open_quantity = 1_000_000_000; max_order_notional = 1_000_000_000_000_000_000L } in
  match Risk.create (List.init (c.agents + 1) (fun id -> id, limits)) with
  | Error e -> Error e
  | Ok initial ->
    let rng = Random.State.make [| c.seed |] in
    let state = ref initial and accepted = ref 0 and rejected = ref 0 and fills = ref 0 and volume = ref 0 in
    let impact_cost = ref 0L and next_id = ref 0 and failure = ref None in
    let execute request =
      let next, status, trades = Risk.apply !state request in
      state := next;
      (match status with Risk.Accepted -> incr accepted | Risk.Rejected _ -> incr rejected);
      fills := !fills + List.length trades;
      volume := !volume + Book.total_traded trades;
      (match Risk.check_invariants next with Ok () -> () | Error e -> failure := Some e);
      trades
    in
    let place account side price quantity policy =
      let id = !next_id in incr next_id;
      execute (Risk.Place { account; id; side; price; quantity; policy })
    in
    (* A symmetric initial depth ladder gives the intervention a fixed reference. *)
    for level = 1 to 20 do
      ignore (place 0 Book.Buy (c.initial_price - level) 100 Risk.Gtc);
      ignore (place 1 Book.Sell (c.initial_price + level) 100 Risk.Gtc)
    done;
    if c.impact_lots > 0 then begin
      let trades = place c.agents Book.Buy (c.initial_price + 100) c.impact_lots Risk.Ioc in
      impact_cost := List.fold_left (fun total (tr : Book.trade) ->
        Int64.add total (Int64.mul (Int64.of_int (tr.price - c.initial_price)) (Int64.of_int tr.quantity))) 0L trades
    end;
    sample (-1) !state;
    for event = 0 to c.events - 1 do
      let account = Random.State.int rng c.agents in
      (* Cancellation bounds resting depth and exercises state cleanup. *)
      if event mod 5 = 0 then ignore (execute (Risk.Halt account));
      if event mod 5 = 0 then ignore (execute (Risk.Resume account));
      let side = if Random.State.bool rng then Book.Buy else Book.Sell in
      let center = match Analytics.quote (Risk.book !state) with
        | None -> c.initial_price
        | Some q -> q.bid_price + (q.ask_price - q.bid_price) / 2 in
      let maker = account mod 3 = 0 in
      let offset = if maker then (if side = Book.Buy then -2 else 2) else Random.State.int rng 11 - 5 in
      let price = max 1 (min 1_000_000_000 (center + offset)) in
      let quantity = 1 + Random.State.int rng 20 in
      ignore (place account side price quantity (if maker then Risk.Post_only else Risk.Ioc));
      sample event !state
    done;
    match !failure with Some e -> Error e | None ->
      let final_mid = Option.map (fun (q : Analytics.quote) -> float q.bid_price +. float q.spread /. 2.) (Analytics.quote (Risk.book !state)) in
      Ok { accepted = !accepted; rejected = !rejected; fills = !fills; volume = !volume; final_mid; impact_cost = !impact_cost; state = !state }
let run c = run_with ~sample:(fun _ _ -> ()) c
let trace ?(max_samples=160) c =
  if max_samples < 2 || max_samples > 1000 then Error "max_samples must be in [2,1000]"
  else
    let stride = max 1 (c.events / max_samples) in
    let samples = ref [] in
    let sample event state =
      if event = -1 || event mod stride = 0 || event = c.events - 1 then
        samples := (event + 1, state) :: !samples in
    match run_with ~sample c with
    | Error e -> Error e
    | Ok report -> Ok (report, List.rev !samples)
let summary c r =
  Printf.sprintf "{\"seed\":%d,\"events\":%d,\"agents\":%d,\"impact_lots\":%d,\"accepted\":%d,\"rejected\":%d,\"fills\":%d,\"volume\":%d,\"final_mid\":%s,\"impact_cost_ticks_lots\":%Ld}"
    c.seed c.events c.agents c.impact_lots r.accepted r.rejected r.fills r.volume
    (match r.final_mid with None -> "null" | Some x -> Printf.sprintf "%.1f" x) r.impact_cost
