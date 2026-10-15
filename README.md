# Exchange in a Box

A deterministic OCaml laboratory for limit order books and market microstructure. The first implementation has a pure price-time-priority matching engine, reproducible event replay, exact tick and lot arithmetic, top-of-book statistics, and an exponential Hawkes likelihood for event arrival times.

This is a research simulator. It has no broker or exchange connectivity and does not make claims about trading profitability.

## Run

Requires OCaml and Dune. The current code uses only the OCaml standard library.

```sh
dune runtest
dune exec exchange-demo
```

## Current semantics

- One instrument, limit orders and cancellations.
- Integer prices in ticks and quantities in lots, with a bound of one billion on each submitted value.
- Best price first, then earliest accepted order at that price.
- Trades execute at the resting order's limit price.
- An accepted order ID can never be reused, including after a full fill or cancellation.
- Invalid submissions and unknown cancellations leave the book unchanged.
- Replay is a pure fold over commands. Identical command sequences produce identical state and outputs.

## Mathematics

The [paper draft](paper/exchange_in_a_box.tex) formalizes the transition system, conservation and book invariants, quote imbalance and microprice, and a stationary exponential Hawkes arrival model. The Hawkes module evaluates the exact point-process log likelihood and compensator increments. These are descriptive tools and hypotheses, not calibrated results.

## Build path

1. Persist a versioned, checksummed event journal and add crash/restart replay.
2. Add timestamps, multiple instruments and venues, plus deterministic latency and fault injection.
3. Add richer order types and a pretrade risk state machine.
4. Build synthetic agent populations and market impact experiments.
5. Fit and compare arrival models with held-out likelihood and time-rescaling diagnostics.
6. Add Async at process boundaries and Incremental for reactive views after the pure core is stable.

The core will remain deterministic; wall-clock time, IO, and concurrency belong at its boundary.
