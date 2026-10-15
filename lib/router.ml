type venue = { name : string; fee_ticks : int; latency_penalty_ticks : int }
type fill =
  { venue : string; maker_id : int; maker_sequence : int; price : int;
    quantity : int; fee_ticks : int; latency_penalty_ticks : int;
    unit_cost : int64 }
type plan =
  { timestamp : int64; instrument : string; side : Book.side;
    requested : int; filled : int; unfilled : int; total_cost : int64;
    trace : fill list }
type candidate = { config : venue; maker : Book.order; rest : Book.order list; cost : int64 }
module Queue = Set.Make (struct
  type t = candidate
  let compare a b =
    let cost = Int64.compare a.cost b.cost in
    if cost <> 0 then cost else
    let venue = String.compare a.config.name b.config.name in
    if venue <> 0 then venue else Int.compare a.maker.sequence b.maker.sequence
end)
module Names = Set.Make (String)
let valid_name s =
  String.length s > 0 && String.length s <= 128 &&
  String.for_all (function 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '-' | '.' -> true | _ -> false) s
let plan state ~instrument ~side ~quantity ~venues =
  let valid_venues =
    let rec loop seen = function
      | [] -> true
      | (v : venue) :: rest ->
          valid_name v.name && not (Names.mem v.name seen)
          && v.fee_ticks >= -1_000_000_000 && v.fee_ticks <= 1_000_000_000
          && v.latency_penalty_ticks >= 0 && v.latency_penalty_ticks <= 1_000_000_000
          && loop (Names.add v.name seen) rest in
    loop Names.empty venues in
  if not (valid_name instrument) then Error "invalid instrument"
  else if quantity <= 0 || quantity > 1_000_000_000 then Error "quantity must be in 1..1000000000"
  else if not valid_venues then Error "invalid or duplicate venue, fee, or latency penalty"
  else
    let push (config : venue) orders queue = match orders with
      | [] -> queue
      | (maker : Book.order) :: rest ->
          let signed_price = match side with Book.Buy -> maker.price | Book.Sell -> -maker.price in
          let cost = Int64.add (Int64.of_int signed_price)
              (Int64.add (Int64.of_int config.fee_ticks) (Int64.of_int config.latency_penalty_ticks)) in
          Queue.add {config;maker;rest;cost} queue in
    let queue = List.fold_left (fun queue config ->
      let book = Engine.book state ~venue:config.name ~instrument in
      push config (match side with Book.Buy -> Book.asks book | Book.Sell -> Book.bids book) queue) Queue.empty venues in
    let rec allocate remaining total trace queue =
      if remaining = 0 || Queue.is_empty queue then
        Ok {timestamp=Engine.clock state;instrument;side;requested=quantity;
            filled=quantity-remaining;unfilled=remaining;total_cost=total;trace=List.rev trace}
      else
        let next = Queue.min_elt queue in
        let take = min remaining next.maker.quantity in
        let fill = {venue=next.config.name;maker_id=next.maker.id;
                    maker_sequence=next.maker.sequence;price=next.maker.price;quantity=take;
                    fee_ticks=next.config.fee_ticks;latency_penalty_ticks=next.config.latency_penalty_ticks;
                    unit_cost=next.cost} in
        let queue = Queue.remove next queue in
        let queue = if take = next.maker.quantity then push next.config next.rest queue else queue in
        allocate (remaining-take) (Int64.add total (Int64.mul next.cost (Int64.of_int take))) (fill::trace) queue
    in allocate quantity 0L [] queue
