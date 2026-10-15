(** Reproducible synthetic populations. Model output is not market calibration. *)
type config = { seed : int; events : int; agents : int; initial_price : int; impact_lots : int }
type report = { accepted : int; rejected : int; fills : int; volume : int; final_mid : float option; impact_cost : int64; state : Risk.t }
val run : config -> (report, string) result
val summary : config -> report -> string
