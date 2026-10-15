# Paired synthetic buy intervention

## Protocol fixed before running the saved study

The study uses seeds 1000 through 1039. Each paired path has 1,000 population
events, 12 population accounts, initial midpoint 10,000 ticks, and a symmetric
ladder with 100 lots at each of 20 bid and ask levels. Liquidity providers and
the intervention account are distinct from population accounts. A buy IOC with
limit 10,020 occurs before the first population event. Shock sizes are 0, 200,
and 800 lots. All combinations are run under Passive (80% maker draws) and
Active (30% maker draws) population regimes. These two regimes and three sizes
are predeclared sensitivities; no best configuration is selected afterward.

The primary outcome is the shocked arm's midpoint minus the control arm's
midpoint after exactly 1,000 population events, in ticks. The secondary outcome
is the intervention's total execution cost relative to the initial midpoint,
in ticks times lots, with filled quantity reported explicitly. The control
executes no intervention, so its intervention cost is zero. This is a cost of
executing extra quantity, not an execution-quality comparison for equal orders.

Every random innovation is drawn once and applied to both arms in lockstep.
The innovation contains account, side, maker draw, offset draw, and quantity.
Neither arm consumes additional random numbers. Prices may adapt to each arm's
own midpoint; this is the mechanism through which the intervention propagates.
Both arms use the same population order IDs. The shock uses a reserved ID and
account. A digest of the common innovation sequence is saved for each pair.
The identical seed also generates the same innovations across size and regime
sensitivities; only the declared maker threshold changes between regimes.

For the 40 midpoint differences in each configuration, report mean, sample
standard deviation, 2.5th percentile, median, and 97.5th percentile. A percentile
bootstrap with 5,000 resamples and seed 20261014 gives an approximate 95% interval
for the mean. Resampling is over whole pairs, never individual arms. Empirical
quantiles interpolate linearly between adjacent sorted observations. Missing
two-sided final quotes produce missing differences, not zero imputation. Report
missing count and label any nonempty missing set as observed-pair-only inference.
Distinct seeds are required. No multiplicity-adjusted significance claim is made.

## Reproduce

`dune exec test/research/experiment_study.exe > docs/results/paired-intervention.csv 2> docs/results/paired-intervention-summary.txt`

`dune runtest` includes zero-shock identity, exact paired replay, invariant
checks after every request, identical innovations across shock sizes, explicit
missing-outcome handling, deterministic bootstrap, and an analytically priced
250-lot ladder sweep.

## Interpretation boundaries

The intervention has a defined counterfactual inside this simulator. Common
random numbers remove variation from using different random inputs in the two
arms. They do not make this population realistic, remove model dependence, or
establish an empirical market causal effect. Agents respond to quotes through
simple declared rules; there is no estimation of strategic behavior, hidden
liquidity, adverse selection, fees, latency, or calibration to exchange data.
The ladder determines initial shock cost mechanically. The bootstrap interval
measures seed variation conditional on this model and protocol, not structural
uncertainty. Reusing seeds across sensitivities makes their estimates dependent.
No simulated outcome establishes trading profitability.

## Saved synthetic results

The saved run contains 240 pairs and 480,000 population arm events, with
invariants checked after every request. All 240 pairs retained two-sided final
quotes. Zero-shock arms were identical. A CSV audit confirmed identical
innovation digests for every seed across all six sensitivities and unchanged
control midpoints across shock sizes within each regime.

| Regime | Buy shock (lots) | Mean final midpoint difference (ticks) | Approximate 95% bootstrap interval |
| --- | ---: | ---: | ---: |
| Passive | 200 | 1.475 | [1.325, 1.625] |
| Passive | 800 | 3.500 | [3.025, 4.025] |
| Active | 200 | 1.1625 | [1.025, 1.300] |
| Active | 800 | 3.950 | [3.4625, 4.425] |

The zero-shock mean and interval are exactly zero in both regimes. The 200-lot
shock fills fully for 300 tick-lots of cost; the 800-lot shock fills fully for
3,600 tick-lots. These costs are identical across seeds because the shock
occurs against the fixed initial ladder. The later midpoint differences vary
with seeded population behavior. They establish a controlled response of this
particular simulator only.

[Pair-level data](results/paired-intervention.csv) and
[distribution summaries](results/paired-intervention-summary.txt) preserve the
observations and intervals, including missing-outcome counts.
