(** Candidate synthetic two-type Hawkes model with shared exponential decay.
    Intensities start from empty history. Matrix entries use target/source order:
    [buy_sell] is the jump in buy intensity caused by a sell event. *)
type parameters =
  { baseline_buy : float; baseline_sell : float
  ; buy_buy : float; buy_sell : float; sell_buy : float; sell_sell : float
  ; decay : float }
type event = { time : float; side : Book.side }
type residual =
  { event : event
  ; component_increment : float
  ; total_increment : float }

val branching_radius : parameters -> (float, string) result
(** Spectral radius of the nonnegative excitation matrix divided by decay.
    Invalid or unrepresentable parameters return Error. *)

val validate : parameters -> (unit, string) result
(** Requires positive finite baselines/decay, nonnegative finite excitation,
    and spectral radius strictly below one. *)

val log_likelihood : parameters -> horizon:float -> event list -> (float, string) result
(** Sum log intensity of the observed type minus the integral of both
    intensities. Events must have strictly increasing global times in [0,T]. *)

val compensator_increments : parameters -> event list -> (residual list, string) result
(** Component increments integrate the corresponding type's intensity since
    its preceding same-type event (or time zero), including all intervening
    opposite-type events. Total increments integrate the sum intensity since
    the preceding event of either type. The final censored tail is omitted. *)

val simulate : seed:int -> max_events:int -> max_candidates:int -> horizon:float ->
  parameters -> (event list, string) result
(** Ogata thinning on the sum intensity followed by conditional type sampling.
    Hard bounds return errors rather than truncated paths. *)
