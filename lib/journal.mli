(** Version 1 append-only event journal, with sequence numbers and MD5 checksums
    for accidental corruption detection (not authentication). Exactly one writer
    must own a path: no concurrent writers, readers during mutation, repair, or
    external modification. Ownership is a caller obligation, not an OS lock.
    Flush and close deliver bytes to the OS, without fsync or power-loss durability. *)
type recovery = { events : Engine.event list; state : Engine.t; outcomes : Engine.outcome list; ignored_tail : bool }
val recover : string -> (recovery, string) result

type writer

(** Validate and replay the existing file once, returning its recovered state and
    a buffered writer at the next sequence. Refuses corrupt and incomplete files.
    A new file receives an immediately flushed version header. *)
val open_writer : string -> (writer * recovery, string) result

(** Append one event in constant overhead plus record encoding cost, without
    rereading the file. Success means buffered acceptance, not durable storage.
    Validation errors leave the writer usable; IO errors invalidate it. *)
val append_writer : writer -> Engine.event -> (unit, string) result
val flush_writer : writer -> (unit, string) result

(** Flush and close. Repeated successful close is harmless. Closed or failed
    writers reject further append/flush calls. *)
val close_writer : writer -> (unit, string) result

(** Convenience operation: open/validate/replay, append, flush and close. Has
    linear validation/replay cost per event; use a writer for long runs. *)
val append : string -> Engine.event -> (unit, string) result

(** Explicitly removes only an incomplete final record after validating the prefix.
    Call only after closing any writer. Complete corrupt records are never erased. *)
val repair_tail : string -> (bool, string) result
