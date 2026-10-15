# Synthetic arrival-model and execution diagnostics

These experiments validate implementation behavior on generated data. They do
not establish fit to a market, causal price impact, profitable trading, or
out-of-sample performance on empirical data.

## Reproduce

Run `dune runtest` for formula, boundary, leakage, and fixed-seed moment checks.
Run `dune exec test/research/research_stress.exe > docs/results/research.csv`
for the saved synthetic study and the million-event stress check. The runner
also has alias `dune build @research-stress`. OCaml's seeded PRNG controls the
paths; reproducibility assumes the same OCaml PRNG implementation.

## Models and observation conventions

The conditional intensity is lambda(t) = mu + alpha sum(exp(-beta(t-ti)))
for events ti < t. Parameters satisfy mu > 0 and 0 <= alpha < beta. Simulation
uses Ogata thinning with an independent local PRNG and explicit event and
candidate budgets. Budget exhaustion is an error. Every path starts at time
zero with empty history, so its initial distribution is not stationary.

Fit uses times up to and including a fixed split, never held-out events.
Poisson uses its exact training rate N/T. A training interval without events
has rate zero; a later event then has held-out log likelihood negative
infinity. Hawkes uses a finite grid, not continuous maximum likelihood:

- baseline = training rate times {0.25, 0.5, 0.75, 1};
- branching ratio = alpha/beta in {0, 0.25, 0.5, 0.75};
- decay beta in {0.3, 0.6, 1.2, 2.4}.

The public API accepts explicit grids. For empty training data, 1/T replaces
the rate in construction of the Hawkes grid only. Parameters maximize training
likelihood. Held-out likelihood integrates only over the held-out interval,
retaining training excitation state at the split. It is evaluated directly,
avoiding cancellation from subtracting large full-interval likelihoods.

Time-rescaling diagnostics use completed interarrival compensator increments
wholly inside the held-out interval. The first interval crossing the split is
omitted. Reported residual mean and Kolmogorov-Smirnov distance from Exp(1) are
descriptive; no p-value or fitted-parameter goodness-of-fit rejection is claimed.
Finite-window termination and parameter estimation affect their distribution.

## Saved run

[CSV results](results/research.csv) contain seeds 100 through 109 for each of:
Poisson (mu=4, alpha=0, beta=1.2) and Hawkes (mu=2, alpha=0.6, beta=1.2).
Horizon is 10,000 and split is 7,000, in arbitrary simulation time units.
Each path permits 200,000 events and 400,000 thinning candidates. Each fit
has 64 grid points. The same seed set is reused across models and is not a
claim of statistically independent pairing between model families.

All ten Poisson paths selected zero excitation. All ten Hawkes paths selected
branching ratio 0.5 and decay 1.2. The generating branching ratio and decay lie on the grid; baseline candidates
are multiples of the observed training rate,
making this a deliberately favorable recovery test. Held-out scores
appear in the CSV, rather than being described as general market evidence.
Alternative grids, regimes, nonstationarity, and model misspecification are
not evaluated by this saved run.

The separate stress path uses seed 20261014, Poisson rate 1, and horizon
1,000,000. It generated 999,409 events. Conditional likelihood from 500,000
to 1,000,000 was exactly -500,000, as required for a unit-rate Poisson model.
This is a correctness and stack-safety check, not a throughput benchmark.

## Execution metrics

`Research.impact` reports filled lots, VWAP, signed slippage versus arrival
midpoint, effective spread, realized spread versus a supplied later midpoint,
and signed midpoint change. They obey effective spread = realized spread +
2 * midpoint change. Positive slippage means a worse price for the taker.
These are descriptive metrics. A causal impact estimate requires a specified
counterfactual and identification design; these metrics alone supply neither.

There are no transaction fees or latency corrections in these metrics. Any
future strategy backtest must specify fees, leakage controls, look-ahead
boundaries, parameter selection, survivorship handling, and regime sensitivity.

## Two-type candidate model

`Marked_hawkes` supplies a buy/sell exponential model with one shared decay
and a nonnegative 2 by 2 excitation matrix. Rows are targets and columns are
sources: `buy_sell` is the jump in buy intensity caused by a sell event.
It requires the spectral radius of the matrix divided by decay to be strictly
below one. This permits asymmetric cross-excitation, including a row sum above
one when the full branching matrix remains subcritical.

The exact marked log likelihood sums log intensity of each observed type and
subtracts integrated buy plus sell intensities, including the final censored
tail. Residuals include both total-intensity interarrival increments and
component increments measured from the previous event of the same type. The
latter retain all opposite-type excitation during that interval. Globally tied
timestamps are rejected because no tie convention is specified for this model.

The bounded seeded simulator thins the sum intensity and samples a type using
its conditional intensity share. `marked_hawkes_test` checks a hand-calculated
three-event likelihood, component residuals, the independent Poisson limit,
critical and asymmetric branching matrices, and exact seed replay. A 40-seed
stress test generated 399,455 events. Its matrix has both column sums equal to
0.5, so the aggregate is exactly a univariate Hawkes process; every total
residual was checked against that independent univariate implementation.
The sample count also satisfies the analytic finite-window first-moment check.
No multivariate fitting or empirical calibration is claimed.
