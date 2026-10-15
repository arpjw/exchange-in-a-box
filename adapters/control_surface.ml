type t = { mutable gateway : Gateway.t; view : Reactive_quote.t; base_revision : int; mutable commands : int }
type action = Output of string | Scenario of Scenario.config | Quit
let create gateway = { gateway; view = Reactive_quote.create (Risk.book (Gateway.state gateway)); base_revision = Gateway.quote_revision gateway; commands = 0 }
let close t = Reactive_quote.close t.view
let state t = t.gateway
let help = String.concat "\n"
  [ "Local exchange research control room"
  ; "  help                          Show commands"
  ; "  status                        Summary of current session"
  ; "  book [DEPTH]                  Individual orders, best price/time first (default 10)"
  ; "  quote                         Incremental top-of-book statistics"
  ; "  accounts                      Positions, cash, halt state and risk limits"
  ; "  place ACCOUNT ID buy|sell PRICE QTY gtc|ioc|fok|post"
  ; "  cancel ACCOUNT ID             Cancel an owned order"
  ; "  halt ACCOUNT                  Cancel all owned orders and block new ones"
  ; "  resume ACCOUNT                Enable new orders"
  ; "  scenario SEED EVENTS [AGENTS [IMPACT_LOTS]]"
  ; "                                Run a fresh synthetic sandbox; keep session book"
  ; "                                EVENTS 0..100000, AGENTS 2..1000 (default 20)"
  ; "  quit                          Exit (EOF also exits)"
  ; "Prices are integer ticks, quantities are lots; cash is ticks*lots."
  ; "This local simulator has no broker or exchange connection."
  ]
let quote t =
  let revision = t.base_revision + Reactive_quote.revision t.view in
  match Reactive_quote.value t.view with
  | None -> Printf.sprintf "QUOTE revision=%d unavailable (two-sided book required)" revision
  | Some q -> Printf.sprintf "QUOTE revision=%d bid=%d x %d ask=%d x %d spread=%d imbalance=%.6f microprice=%.6f"
      revision q.bid_price q.bid_quantity q.ask_price q.ask_quantity q.spread q.imbalance q.microprice
let overview t =
  let risk = Gateway.state t.gateway in
  let b = Risk.book risk in
  Printf.sprintf "SESSION commands=%d accounts=%d resting_bids=%d resting_asks=%d accepted_ids=%d\n%s"
    t.commands (List.length (Risk.accounts risk)) (List.length (Book.bids b)) (List.length (Book.asks b)) (Book.seen_count b) (quote t)
let take n xs =
  let rec loop n xs acc = match xs with [] -> List.rev acc | _ when n = 0 -> List.rev acc | x::rest -> loop (n-1) rest (x::acc) in
  loop n xs []
let book t depth =
  let book = Risk.book (Gateway.state t.gateway) in
  let rows name orders =
    let lines = take depth orders |> List.map (fun (o : Book.order) ->
      Printf.sprintf "  %-12d %-12d %-12d %-12d" o.id o.price o.quantity o.sequence) in
    name ^ "\n  ID           PRICE        QUANTITY     SEQUENCE\n" ^
    (if lines = [] then "  (empty)" else String.concat "\n" lines) ^
    (if List.length orders > depth then Printf.sprintf "\n  ... %d more orders" (List.length orders - depth) else "")
  in String.concat "\n" [quote t; rows "BIDS" (Book.bids book); rows "ASKS" (Book.asks book)]
let accounts t =
  (* Ownership is intentionally encapsulated by Risk. Open quantities are shown
     in aggregate in the session book, while the table exposes account limits. *)
  let rows = Risk.accounts (Gateway.state t.gateway) |> List.map (fun (a : Risk.account) ->
    Printf.sprintf "%-8d %-10d %-20Ld %-8s %-12d %-12d %Ld" a.id a.position a.cash
      (if a.halted then "HALTED" else "ACTIVE") a.limits.max_position a.limits.max_open_quantity a.limits.max_order_notional) in
  "ACCOUNT  POSITION   CASH                 STATE    MAX_POSITION MAX_OPEN_QTY MAX_ORDER_NOTIONAL\n" ^ String.concat "\n" rows
let command t line =
  let tokens = String.split_on_char ' ' (String.trim line) |> List.filter ((<>) "") in
  match tokens with
  | [] -> Output ""
  | ["quit"] | ["exit"] -> Quit
  | ["help"] | ["?"] -> Output help
  | ["status"] -> Output (overview t)
  | ["quote"] -> Output (quote t)
  | ["accounts"] -> Output (accounts t)
  | ["book"] -> Output (book t 10)
  | ["book"; n] ->
    (match int_of_string_opt n with Some n when n >= 1 && n <= 100 -> Output (book t n) | _ -> Output "ERROR: book depth must be 1..100")
  | "scenario" :: args ->
    (try
       let seed, events, agents, impact_lots = match List.map int_of_string args with
         | [s;e] -> s,e,20,0 | [s;e;a] -> s,e,a,0 | [s;e;a;i] -> s,e,a,i | _ -> invalid_arg "scenario" in
       if events < 0 || events > 100000 || agents < 2 || agents > 1000 || impact_lots < 0 || impact_lots > 1000000 then invalid_arg "scenario";
       Scenario { seed; events; agents; impact_lots; initial_price = 10000 }
     with Invalid_argument _ | Failure _ -> Output "ERROR: scenario SEED EVENTS [AGENTS [IMPACT_LOTS]]; EVENTS 0..100000, AGENTS 2..1000, IMPACT_LOTS 0..1000000")
  | ("place" | "cancel" | "halt" | "resume") :: _ ->
    let gateway, response = Gateway.handle t.gateway line in
    t.gateway <- gateway;
    t.commands <- t.commands + 1;
    Reactive_quote.set_book t.view (Risk.book (Gateway.state gateway));
    Reactive_quote.stabilize t.view;
    Output (response ^ "\n" ^ quote t)
  | _ -> Output "ERROR: unknown command; type help"
