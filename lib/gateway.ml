type t = { state : Risk.t; quote : Analytics.quote option; revision : int }
let create accounts = Result.map (fun state -> { state; quote = None; revision = 0 }) (Risk.create accounts)
let state t = t.state
let quote_revision t = t.revision
let side = function "buy" -> Book.Buy | "sell" -> Book.Sell | _ -> invalid_arg "side"
let policy = function "gtc" -> Risk.Gtc | "ioc" -> Risk.Ioc | "fok" -> Risk.Fok | "post" -> Risk.Post_only | _ -> invalid_arg "policy"
let reason = function
  | Risk.Unknown_account -> "unknown_account" | Risk.Halted -> "halted" | Risk.Unauthorized -> "unauthorized"
  | Risk.Limit -> "risk_limit" | Risk.Would_cross -> "would_cross" | Risk.Cannot_fill -> "cannot_fill"
  | Risk.Self_trade -> "self_trade" | Risk.Engine Book.Invalid_order -> "invalid_order"
  | Risk.Engine Book.Duplicate_id -> "duplicate_id" | Risk.Engine Book.Unknown_id -> "unknown_id"
let quote_json = function
  | None -> "null"
  | Some (q : Analytics.quote) -> Printf.sprintf "{\"bid\":%d,\"ask\":%d,\"bid_quantity\":%d,\"ask_quantity\":%d,\"imbalance\":%.17g,\"microprice\":%.17g}"
      q.bid_price q.ask_price q.bid_quantity q.ask_quantity q.imbalance q.microprice
let account_json (a : Risk.account) = Printf.sprintf "{\"id\":%d,\"position\":%d,\"cash\":\"%Ld\",\"halted\":%b}" a.id a.position a.cash a.halted
let handle t line =
  let tokens = String.split_on_char ' ' (String.trim line) |> List.filter ((<>) "") in
  match tokens with
  | ["quote"] -> t, Printf.sprintf "{\"revision\":%d,\"quote\":%s}" t.revision (quote_json t.quote)
  | ["accounts"] -> t, "{\"accounts\":[" ^ String.concat "," (List.map account_json (Risk.accounts t.state)) ^ "]}"
  | _ ->
    let parsed = try Some (match tokens with
      | ["place"; account; id; direction; price; quantity; tif] ->
          Risk.Place { account = int_of_string account; id = int_of_string id; side = side direction;
                       price = int_of_string price; quantity = int_of_string quantity; policy = policy tif }
      | ["cancel"; account; id] -> Risk.Cancel { account = int_of_string account; id = int_of_string id }
      | ["halt"; account] -> Risk.Halt (int_of_string account)
      | ["resume"; account] -> Risk.Resume (int_of_string account)
      | _ -> invalid_arg "command") with Invalid_argument _ | Failure _ -> None in
    match parsed with
    | None -> t, "{\"status\":\"error\",\"reason\":\"invalid_command\"}"
    | Some command ->
      let state, status, trades = Risk.apply t.state command in
      let quote = Analytics.quote (Risk.book state) in
      let revision = t.revision + if quote = t.quote then 0 else 1 in
      let status_json = match status with Risk.Accepted -> "\"status\":\"accepted\"" | Risk.Rejected r -> "\"status\":\"rejected\",\"reason\":\"" ^ reason r ^ "\"" in
      let trades_json = List.map (fun (tr : Book.trade) -> Printf.sprintf "{\"maker\":%d,\"taker\":%d,\"price\":%d,\"quantity\":%d}" tr.maker_id tr.taker_id tr.price tr.quantity) trades |> String.concat "," in
      { state; quote; revision }, Printf.sprintf "{%s,\"revision\":%d,\"trades\":[%s]}" status_json revision trades_json
