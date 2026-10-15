(** Paired interventions inside a synthetic market, not empirical causal estimates.
    Both arms consume each generated population innovation exactly once. *)
type regime = Passive | Active
type config =
  { seed : int; events : int; agents : int; initial_price : int
  ; shock_lots : int; regime : regime }
type pair =
  { seed : int; control_mid : float option; shocked_mid : float option
  ; midpoint_difference : float option
  ; shock_filled_lots : int; shock_cost_ticks_lots : int64
  ; innovation_digest : string }
val run_pair : config -> (pair, string) result
(** Bounded buy IOC occurs before population events. Its limit is initial+20.
    Baseline ladder has 100 lots at each of 20 levels on both sides. Population
    accounts are distinct from liquidity providers and the intervention account. *)

type summary =
  { pairs : int; observed : int; missing : int; mean : float option
  ; sample_sd : float option; q025 : float option; median : float option
  ; q975 : float option; bootstrap_low : float option; bootstrap_high : float option }
val summarize : bootstrap_seed:int -> resamples:int -> pair list -> (summary, string) result
(** Percentile bootstrap interval for the mean of observed paired midpoint
    differences. It is approximate, conditional on this synthetic population and
    any observed-only selection. Duplicate seeds are rejected. At least two
    observations are required for an interval; missing outcomes are counted. *)
