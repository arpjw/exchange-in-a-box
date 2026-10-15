# Browser lab

The Vercel site is a static shell around OCaml code compiled with `js_of_ocaml`.
The bridge exports JSON-returning functions for manual risk requests, sampled
`Scenario.trace` replay, `Router.plan`, and `Experiment.run_pair`. The browser
stores view state only. It cannot enter real orders or call a broker.

## Build and run

Install the repository's opam dependencies, then run:

```sh
bash scripts/build-web.sh
python3 -m http.server 8788 --directory web/public
```

Open `http://localhost:8788`. Rebuild after changing OCaml core code or the
local LaTeX source's exported PDF. The generated bundle and `paper.pdf` are
checked in because Vercel serves `web/public` without installing opam.

`node scripts/test-web.cjs` checks that the compiled JavaScript bridge returns
the same deterministic state as native OCaml paths. `dune runtest` checks trace
parity and core invariants. Keep the native and browser gates in CI.

## Interface boundaries

- Market replay samples states from the same `Scenario.run` execution. The
  slider changes the displayed sampled state, not the simulator state.
- The order sandbox uses `Risk.apply` for GTC, IOC, FOK, post-only, cancel,
  halt, and resume. All data is local to one browser page and resets on reload.
- The router uses a fixed three-venue synthetic book with editable fees. Its
  latency penalties are objective weights, not measured delays. Plans are not
  submitted.
- A paired run uses a single seed, while the saved 40-seed table comes from
  `docs/results/paired-intervention.csv` and is labeled separately.
- Async, Incremental, and journal IO stay in the native application. Browser
  bundles contain no account credentials or exchange connections.
