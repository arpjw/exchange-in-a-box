(** Pure account ledger and pretrade checks for a single instrument. Short positions
    are allowed within limits. Cash is an accounting balance, not collateral. *)
type policy = Gtc | Ioc | Fok | Post_only
type limits = { max_position : int; max_open_quantity : int; max_order_notional : int64 }
type account = { id : int; position : int; cash : int64; halted : bool; limits : limits }
type request =
  | Place of { account : int; id : int; side : Book.side; price : int; quantity : int; policy : policy }
  | Cancel of { account : int; id : int }
  | Halt of int
  | Resume of int
type rejection = Unknown_account | Halted | Unauthorized | Limit | Would_cross | Cannot_fill | Self_trade | Engine of Book.rejection
type status = Accepted | Rejected of rejection
type t
val create : (int * limits) list -> (t, string) result
val book : t -> Book.t
val accounts : t -> account list
val apply : t -> request -> t * status * Book.trade list
val check_invariants : t -> (unit, string) result
