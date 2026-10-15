(** Reproducible synthetic experiments. All model fits use training data only.
    Simulation starts with empty history, not the stationary distribution. *)

val simulate_hawkes :
  seed:int -> max_events:int -> max_candidates:int -> horizon:float ->
  Analytics.Hawkes.parameters -> (float list, string) result
(** Ogata thinning with explicit resource bounds. Exceeding a bound returns an
    error, never a silently truncated path. The caller owns the fixed seed. *)

type fit =
  { parameters : Analytics.Hawkes.parameters
  ; training_log_likelihood : float
  ; heldout_log_likelihood : float
  ; residual_mean : float option
  ; residual_ks : float option
  ; residual_count : int
  }

type comparison =
  { poisson : fit
  ; hawkes : fit
  ; training_events : int
  ; heldout_events : int
  ; hawkes_candidates : int
  }

val compare :
  split:float -> horizon:float -> decays:float list ->
  branching_ratios:float list -> baseline_multipliers:float list ->
  float list -> (comparison, string) result
(** Chronological split: training events are <= split, test events > split.
    Poisson uses its training MLE (zero is allowed for an empty training set).
    Hawkes uses a finite supplied grid with baseline = training rate * multiplier.
    Empty training data uses 1/split to construct the Hawkes grid.
    Held-out likelihood conditions on the full training history.
    KS measures distance of completed held-out compensator increments from
    Exp(1); the interval crossing split is omitted. No fitted-model p-value is
    claimed. Grid search is not continuous maximum likelihood estimation. *)

val conditional_log_likelihood :
  Analytics.Hawkes.parameters -> start:float -> horizon:float ->
  float list -> (float, string) result
(** Includes pre-start history in intensity and integrates only (start,horizon].
    Events at start belong to the history. *)

type impact =
  { filled_lots : int
  ; vwap : float
  ; slippage_ticks : float
  ; effective_spread_ticks : float
  ; realized_spread_ticks : float
  ; midpoint_impact_ticks : float
  }

val impact :
  side:Book.side -> arrival_mid:float -> later_mid:float ->
  Book.trade list -> (impact option, string) result
(** Positive slippage means worse execution for the taker. Realized spread is
    2*side*(VWAP-later_mid); midpoint impact is side*(later_mid-arrival_mid).
    These descriptive metrics do not identify causal impact. Empty fills -> None. *)
