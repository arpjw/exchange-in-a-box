(** A pure, single-instrument, price-time-priority limit order book.
    Prices are integer ticks and quantities are integer lots. *)

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
type t

val empty : t
val bids : t -> order list
val asks : t -> order list
val seen_count : t -> int
val apply : t -> command -> t * status * trade list
val replay : command list -> t * (status * trade list) list
val check_invariants : t -> (unit, string) result
val total_traded : trade list -> int
