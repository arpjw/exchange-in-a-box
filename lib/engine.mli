(** Deterministic routing. Order IDs are scoped to a venue/instrument pair. *)
type event = { timestamp : int64; venue : string; instrument : string; command : Book.command }
type outcome = Applied of Book.status * Book.trade list | Invalid_route | Time_regression
type t
val empty : t
val clock : t -> int64
val book : t -> venue:string -> instrument:string -> Book.t
val apply : t -> event -> t * outcome
val replay : event list -> t * outcome list
val check_invariants : t -> (unit, string) result

(** Delivery order is arrival time, then input position. Drops are explicit and
    latency is a pure function of input position. Negative/overflow times fail. *)
val schedule : latency:(int -> int64) -> drop:(int -> bool) -> event list -> (event list, string) result
