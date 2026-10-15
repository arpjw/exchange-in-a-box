(** Static, pure cross-venue depth allocation for one instrument. Displayed depth
    is assumed executable without competing flow, price changes, lot-size
    differences, or partial-fill uncertainty. Fees and latency penalties are
    constant integer ticks per lot at each venue. This is a research planner;
    latency penalties are chosen objective weights, not measured execution costs.
    No orders are submitted and Engine state is unchanged. *)
type venue = { name : string; fee_ticks : int; latency_penalty_ticks : int }
type fill =
  { venue : string; maker_id : int; maker_sequence : int; price : int;
    quantity : int; fee_ticks : int; latency_penalty_ticks : int;
    unit_cost : int64 }
type plan =
  { timestamp : int64; instrument : string; side : Book.side;
    requested : int; filled : int; unfilled : int; total_cost : int64;
    trace : fill list }

(** Minimize total cost among allocations filling as much requested quantity as
    available. Buy cost = price + fee + latency penalty; sell cost = -price + fee
    + latency penalty (equivalently maximize proceeds less fees and penalties).
    A fee may be negative for a rebate. Each route's maker price-time queue is
    preserved. Equal costs across venues use lexicographic venue names, so venue
    input order never affects output. Trace follows allocation order, one item
    per consumed maker, with a possible partial final maker.

    Names obey Engine's route alphabet and length. Venue names must be unique.
    Quantity must be 1..1e9, fee -1e9..1e9, and latency penalty 0..1e9, ensuring
    every total fits int64. Missing books and an empty venue list mean no depth. *)
val plan : Engine.t -> instrument:string -> side:Book.side -> quantity:int ->
  venues:venue list -> (plan, string) result
