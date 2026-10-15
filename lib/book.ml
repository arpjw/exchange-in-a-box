type side = Buy | Sell

type order =
  { id : int
  ; side : side
  ; price : int
  ; quantity : int
  ; sequence : int
  }

type command =
  | Submit of { id : int; side : side; price : int; quantity : int }
  | Cancel of int

type trade =
  { maker_id : int
  ; taker_id : int
  ; price : int
  ; quantity : int
  }

type rejection = Invalid_order | Duplicate_id | Unknown_id
type status = Accepted | Rejected of rejection

module Ids = Set.Make (Int)

type t =
  { bids : order list
  ; asks : order list
  ; seen : Ids.t
  ; next_sequence : int
  }

let empty = { bids = []; asks = []; seen = Ids.empty; next_sequence = 0 }
let bids t = t.bids
let asks t = t.asks
let seen_count t = Ids.cardinal t.seen

let ahead side (a : order) (b : order) =
  let price_first =
    match side with
    | Buy -> a.price > b.price
    | Sell -> a.price < b.price
  in
  price_first || (a.price = b.price && a.sequence < b.sequence)

let insert side order orders =
  let rec loop prefix = function
    | [] -> List.rev_append prefix [order]
    | head :: tail as rest ->
        if ahead side order head then List.rev_append prefix (order :: rest)
        else loop (head :: prefix) tail
  in
  loop [] orders

let crosses (taker : order) (maker : order) =
  match taker.side with
  | Buy -> taker.price >= maker.price
  | Sell -> taker.price <= maker.price

let rec match_orders (taker : order) (makers : order list) trades =
  match makers with
  | maker :: tail when taker.quantity > 0 && crosses taker maker ->
      let quantity = min taker.quantity maker.quantity in
      let trade = { maker_id = maker.id; taker_id = taker.id; price = maker.price; quantity } in
      let taker = { taker with quantity = taker.quantity - quantity } in
      let makers =
        if quantity = maker.quantity then tail
        else { maker with quantity = maker.quantity - quantity } :: tail
      in
      match_orders taker makers (trade :: trades)
  | _ -> taker, makers, List.rev trades

let remove id orders =
  let rec loop prefix = function
    | [] -> None
    | order :: tail when order.id = id -> Some (List.rev_append prefix tail)
    | order :: tail -> loop (order :: prefix) tail
  in
  loop [] orders

let apply t = function
  | Cancel id ->
      (match remove id t.bids with
       | Some bids -> { t with bids }, Accepted, []
       | None ->
           (match remove id t.asks with
            | Some asks -> { t with asks }, Accepted, []
            | None -> t, Rejected Unknown_id, []))
  | Submit { id; side; price; quantity } ->
      if id < 0 || price <= 0 || quantity <= 0 || price > 1_000_000_000
         || quantity > 1_000_000_000
      then t, Rejected Invalid_order, []
      else if Ids.mem id t.seen then t, Rejected Duplicate_id, []
      else
        let order = { id; side; price; quantity; sequence = t.next_sequence } in
        let t = { t with seen = Ids.add id t.seen; next_sequence = t.next_sequence + 1 } in
        match side with
        | Buy ->
            let remainder, asks, trades = match_orders order t.asks [] in
            let bids =
              if remainder.quantity = 0 then t.bids else insert Buy remainder t.bids
            in
            { t with bids; asks }, Accepted, trades
        | Sell ->
            let remainder, bids, trades = match_orders order t.bids [] in
            let asks =
              if remainder.quantity = 0 then t.asks else insert Sell remainder t.asks
            in
            { t with bids; asks }, Accepted, trades

let replay commands =
  let book, reverse_results =
    List.fold_left
      (fun (book, results) command ->
        let book, status, trades = apply book command in
        book, (status, trades) :: results)
      (empty, []) commands
  in
  book, List.rev reverse_results

let check_invariants t =
  let check_side side orders =
    let rec loop = function
      | [] -> true
      | [ order ] -> order.side = side && order.quantity > 0
      | a :: (b :: _ as rest) ->
          a.side = side && a.quantity > 0 && ahead side a b && loop rest
    in
    loop orders
  in
  let orders = t.bids @ t.asks in
  if not (check_side Buy t.bids && check_side Sell t.asks) then
    Error "orders violate side, positive quantity, or price-time priority"
  else if List.exists (fun order -> not (Ids.mem order.id t.seen)) orders then
    Error "resting order is missing from the seen-id registry"
  else if List.length (List.sort_uniq Int.compare (List.map (fun o -> o.id) orders))
          <> List.length orders
  then Error "duplicate resting order id"
  else
    match t.bids, t.asks with
    | bid :: _, ask :: _ when bid.price >= ask.price -> Error "crossed book"
    | _ -> Ok ()

let total_traded trades =
  List.fold_left (fun total trade -> total + trade.quantity) 0 trades
