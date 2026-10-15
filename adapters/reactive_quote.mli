(** Jane Street Incremental graph. Each instance owns a book variable and quote
    observer. Call [stabilize] after one or more [set_book] operations. *)
type t
val create : Book.t -> t
val set_book : t -> Book.t -> unit
val stabilize : t -> unit
val value : t -> Analytics.quote option
val revision : t -> int
val close : t -> unit
