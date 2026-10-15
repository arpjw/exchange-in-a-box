let obj xs = `Assoc xs
let num x = `Int x
let str x = `String x
let bool x = `Bool x
let list xs = `List xs
let decimal x = `Float x
let int64 x = str (Int64.to_string x)
let optional f = function None -> `Null | Some x -> f x

let order (o : Book.order) = obj [
  "id", num o.id; "side", str (if o.side = Buy then "buy" else "sell");
  "price", num o.price; "quantity", num o.quantity; "sequence", num o.sequence ]

let trade (t : Book.trade) = obj [
  "maker", num t.maker_id; "taker", num t.taker_id;
  "price", num t.price; "quantity", num t.quantity ]

let quote book = optional (fun (q : Analytics.quote) -> obj [
  "bid", num q.bid_price; "bidQty", num q.bid_quantity;
  "ask", num q.ask_price; "askQty", num q.ask_quantity;
  "spread", num q.spread; "imbalance", decimal q.imbalance;
  "microprice", decimal q.microprice ]) (Analytics.quote book)

let account (a : Risk.account) = obj [
  "id", num a.id; "position", num a.position;
  "cash", int64 a.cash; "halted", bool a.halted;
  "maxPosition", num a.limits.max_position;
  "maxOpen", num a.limits.max_open_quantity ]

let book state =
  let b = Risk.book state in
  [ "bids", list (List.map order (Book.bids b));
    "asks", list (List.map order (Book.asks b));
    "quote", quote b;
    "accounts", list (List.map account (Risk.accounts state)) ]

let status = function
  | Risk.Accepted -> "accepted"
  | Risk.Rejected Risk.Unknown_account -> "unknown account"
  | Risk.Rejected Risk.Halted -> "account halted"
  | Risk.Rejected Risk.Unauthorized -> "unauthorized or unknown order"
  | Risk.Rejected Risk.Limit -> "risk limit"
  | Risk.Rejected Risk.Would_cross -> "post-only would cross"
  | Risk.Rejected Risk.Cannot_fill -> "fill-or-kill cannot fill"
  | Risk.Rejected Risk.Self_trade -> "self trade"
  | Risk.Rejected (Risk.Engine Book.Invalid_order) -> "invalid order"
  | Risk.Rejected (Risk.Engine Book.Duplicate_id) -> "duplicate id"
  | Risk.Rejected (Risk.Engine Book.Unknown_id) -> "unknown id"

type session = { mutable state : Risk.t; mutable next_id : int; mutable revision : int }

let make_session () =
  let limits : Risk.limits = {
    max_position = 100_000; max_open_quantity = 100_000;
    max_order_notional = 1_000_000_000L } in
  match Risk.create (List.init 8 (fun id -> id, limits)) with
  | Error e -> failwith e
  | Ok state ->
    let s = { state; next_id = 1000; revision = 0 } in
    let place account id side price quantity =
      let state, _, _ = Risk.apply s.state
        (Risk.Place { account; id; side; price; quantity; policy = Risk.Gtc }) in
      s.state <- state in
    for level = 1 to 8 do
      place 0 (2 * level) Book.Buy (10_000 - level) (100 + 15 * level);
      place 1 (2 * level + 1) Book.Sell (10_000 + level) (100 + 15 * level)
    done;
    s

let snapshot ?(event="ready") ?(trades=[]) s = obj
  ([ "event", str event; "revision", num s.revision;
     "trades", list (List.map trade trades) ] @ book s.state)

let apply s request =
  let next, result, trades = Risk.apply s.state request in
  if result = Risk.Accepted then (s.state <- next; s.revision <- s.revision + 1);
  snapshot ~event:(status result) ~trades s

let place s ~account ~side ~price ~quantity ~policy =
  let side = match String.lowercase_ascii side with
    | "buy" -> Some Book.Buy | "sell" -> Some Book.Sell | _ -> None in
  let policy = match String.lowercase_ascii policy with
    | "gtc" -> Some Risk.Gtc | "ioc" -> Some Risk.Ioc
    | "fok" -> Some Risk.Fok | "post" -> Some Risk.Post_only | _ -> None in
  match side, policy with
  | Some side, Some policy ->
      let id = s.next_id in s.next_id <- id + 1;
      let result = apply s (Risk.Place {account; id; side; price; quantity; policy}) in
      (match result with `Assoc xs -> `Assoc (("orderId", num id) :: xs) | _ -> result)
  | _ -> snapshot ~event:"invalid side or policy" s

let scenario ~seed ~events ~agents ~impact_lots =
  if events < 0 || events > 10_000 then obj ["error", str "events must be between 0 and 10000"]
  else
    let config : Scenario.config = { seed; events; agents; initial_price = 10_000; impact_lots } in
    match Scenario.trace ~max_samples:120 config with
    | Error e -> obj ["error", str e]
    | Ok (r, samples) ->
        obj [ "seed", num seed; "events", num events; "agents", num agents;
              "impactLots", num impact_lots;
              "accepted", num r.accepted; "rejected", num r.rejected;
              "fills", num r.fills; "volume", num r.volume;
              "finalMid", optional decimal r.final_mid;
              "impactCost", int64 r.impact_cost;
              "frames", list (List.map (fun (event, state) ->
                obj (("step", num event) :: book state)) samples) ]

let intervention ~seed ~events ~shock_lots ~regime =
  if events < 0 || events > 2_000 then obj ["error", str "events must be between 0 and 2000"]
  else
    let regime = if String.lowercase_ascii regime = "active" then
      Experiment.Active else Experiment.Passive in
    let config : Experiment.config = {
      seed; events; agents = 12; initial_price = 10_000; shock_lots; regime } in
    match Experiment.run_pair config with
    | Error e -> obj ["error", str e]
    | Ok p -> obj [
        "seed", num p.seed;
        "controlMid", optional decimal p.control_mid;
        "shockMid", optional decimal p.shocked_mid;
        "difference", optional decimal p.midpoint_difference;
        "filledLots", num p.shock_filled_lots;
        "shockCost", int64 p.shock_cost_ticks_lots;
        "innovationDigest", str p.innovation_digest ]

let route ~side ~quantity ~fees =
  if quantity < 1 || quantity > 1_000 then obj ["error", str "quantity must be in [1,1000]"]
  else
    let venues = ["ALPHA"; "BETA"; "GAMMA"] in
    let base = [| 0; -1; 1 |] in
    let engine = ref Engine.empty and timestamp = ref 0L in
    List.iteri (fun index venue ->
      for level = 1 to 6 do
        List.iter (fun side ->
          let price = if side = Book.Buy then
            10_000 + base.(index) - level else 10_000 + base.(index) + level in
          let id = index * 100 + level * 2 + (if side = Book.Buy then 0 else 1) in
          let event : Engine.event = {
            timestamp = !timestamp; venue; instrument = "SYN";
            command = Book.Submit { id; side; price; quantity = 45 + level * 18 } } in
          let next, _ = Engine.apply !engine event in
          engine := next; timestamp := Int64.succ !timestamp) [Book.Buy; Book.Sell]
      done) venues;
    let side = if String.lowercase_ascii side = "sell" then Book.Sell else Book.Buy in
    let candidates = List.mapi (fun i name ->
      let fee = try List.nth fees i with _ -> 0 in
      ({ Router.name = name; fee_ticks = fee; latency_penalty_ticks = List.nth [1; 2; 0] i } : Router.venue)) venues in
    match Router.plan !engine ~instrument:"SYN" ~side ~quantity ~venues:candidates with
    | Error e -> obj ["error", str e]
    | Ok p -> obj [
        "requested", num p.requested; "filled", num p.filled;
        "unfilled", num p.unfilled; "totalCost", int64 p.total_cost;
        "side", str (if side = Book.Buy then "buy" else "sell");
        "fills", list (List.map (fun (f : Router.fill) -> obj [
          "venue", str f.venue; "maker", num f.maker_id;
          "price", num f.price; "quantity", num f.quantity;
          "fee", num f.fee_ticks; "latency", num f.latency_penalty_ticks;
          "unitCost", int64 f.unit_cost ]) p.trace) ]

let encode x = Yojson.Basic.to_string x
