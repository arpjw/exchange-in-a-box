(** Local terminal presentation over the pure gateway and Incremental quote graph. *)
type t
type action = Output of string | Scenario of Scenario.config | Quit
val create : Gateway.t -> t
val close : t -> unit
val state : t -> Gateway.t
val help : string
val overview : t -> string
val command : t -> string -> action
