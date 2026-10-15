# Exchange in a Box

A deterministic OCaml laboratory for limit order books and market microstructure. It combines a pure matching core, multi-route replay, a checksummed event journal, account risk controls, synthetic populations, and point-process research. Async and Incremental adapters provide a live protocol boundary and reactive quotes while keeping the core deterministic.

This is a research simulator. It has no broker or exchange connectivity and does not make claims about trading profitability.

## Run

Requires OCaml 5.1 or later, Dune, Python 3 for subprocess tests, and the declared Async and Incremental packages. The pure `exchange_in_a_box` core uses only the OCaml standard library; `exchange_in_a_box.adapters` holds the Jane Street integrations.

```sh
dune runtest
dune exec exchange-demo
dune exec exchange-scenario -- --seed 42 --events 10000 --agents 20 --impact-lots 250
dune exec exchange-async-worker
dune exec exchange-control-room
bash scripts/demo_control_room.sh
bash scripts/stress.sh
bash scripts/build-web.sh
```

## Browser lab

The [browser lab](web/README.md) runs the pure OCaml matching, risk, scenario, routing, and paired-intervention modules through `js_of_ocaml`. It offers a sampled market replay, manual order sandbox, static cross-venue planner, and paired synthetic comparison. Vercel serves only `web/public`; the checked-in browser bundle and paper PDF are rebuilt with `bash scripts/build-web.sh` after core or paper changes. Browser calculations use the same OCaml modules as native tests. The Async worker, Incremental adapter, and journal remain native-only.

## Implemented system

- Price-time-priority limit books with submissions and cancellations. Prices and quantities are integer ticks and lots, bounded at one billion per submission.
- Best price first, then earliest accepted order at that price.
- Trades execute at the resting order's limit price.
- An accepted order ID can never be reused, including after a full fill or cancellation.
- Invalid submissions and unknown cancellations leave the book unchanged.
- Multi-venue and multi-instrument routing, with IDs scoped to a route. Replay is a pure fold over timestamped events.
- Deterministic delivery scheduling with latency, stable ties, and explicit drops.
- Versioned, checksummed journal with complete-record validation, incomplete-tail recovery, and a buffered single-writer API.
- Single-instrument account controls: positions, cash, order reservations, limits, halt/resume, authorized cancellation, and GTC, IOC, FOK, and post-only policies.
- Synchronous and Async line-protocol workers. Incremental observes derived quotes and suppresses unchanged updates.
- Seeded synthetic populations and reproducible scenario reports.
- Static cross-venue routing plans that maximize displayed fill and minimize configured price, fee, and latency-weighted cost.
- A terminal control room for book depth, quotes, account risk, order actions, and seeded scenarios. See [control room usage](scripts/CONTROL_ROOM.md).

## Mathematics

The [paper draft](paper/exchange_in_a_box.pdf) formalizes matching and ledger invariants, static routing optimality, quote imbalance and microprice, and one- and two-type exponential Hawkes models. The code evaluates exact likelihoods and compensator increments, simulates bounded seeded paths, and compares Poisson with a finite-grid univariate Hawkes fit on a chronological holdout. A [paired synthetic intervention](docs/paired-intervention.md) shares population innovations between shocked and control books and reports saved seed-level results. [Research methods and saved arrival-model results](docs/research.md) document the evaluation and its limits. These are synthetic and software-validation results, not calibrated market findings. The repository contains the PDF; the editable LaTeX source remains local.

## Validation

`dune runtest` covers directed invariants, journal corruption and truncation, risk-policy atomicity, a seeded exhaustive routing oracle, point-process formulas, paired intervention identity, and real worker subprocesses. `bash scripts/stress.sh` builds and runs the full suite plus repeated multi-seed scenario determinism checks. [Runtime and stress details](scripts/README.md) include larger-run settings. GitHub Actions runs the same gates on pushes and pull requests.

## Boundaries

The journal persists routed matching-engine commands, not account-risk requests or ledger state. Risk and both workers are single-instrument, in-memory research interfaces. The journal assumes an exclusive writer and does not call `fsync`; a successful flush is not a power-loss durability guarantee. The models and scenario metrics use synthetic data. There is no broker connectivity, market calibration, transaction-cost backtest, causal impact estimate, or supported profitability claim.
