(** Sequential deterministic state transitions over nonblocking Async IO.
    Processes one line at a time and waits for output flush before reading another.
    The caller owns and closes the reader/writer. EOF returns the final state. *)
val serve : reader:Async.Reader.t -> writer:Async.Writer.t -> Gateway.t -> Gateway.t Async.Deferred.t
