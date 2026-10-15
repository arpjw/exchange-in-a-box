(** Line protocol boundary shared by synchronous or asynchronous frontends.
    Cached quote revisions advance only when top-of-book statistics change. *)
type t
val create : (int * Risk.limits) list -> (t, string) result
val state : t -> Risk.t
val quote_revision : t -> int
val handle : t -> string -> t * string
