# Runtime and validation

`dune exec exchange-scenario -- --seed 42 --events 10000 --agents 20 --impact-lots 250`
prints a JSON summary of a reproducible synthetic experiment. The initial symmetric
ladder contains 100 lots at each of 20 tick levels per side. A buy intervention
executes against that ladder before the random population starts. Its reported
cost is the sum of `(execution price - initial reference price) * filled lots`.
Unfilled IOC quantity expires. Populations combine passive quote placement,
aggressive flow, and periodic account cancellation. These are synthetic mechanics,
not calibrated market behavior or trading performance estimates.

`dune exec exchange-worker` reads commands from stdin, emits one JSON response per
line, flushes after each response, and terminates on EOF. This is a synchronous
standard-library boundary. `Gateway.handle` is pure and can also be used by other
frontends. Quote revisions are cached and advance only when the derived two-sided
quote changes. A one-sided book has a null quote.

```
place 0 1 buy 99 10 gtc
place 1 2 sell 101 10 post
quote
place 0 3 buy 101 5 ioc
accounts
cancel 0 1
halt 1
resume 1
```

`place` accepts an account ID, order ID, side (`buy` or `sell`), integer price,
integer quantity and policy (`gtc`, `ioc`, `fok`, or `post`). `halt` cancels all
resting orders for an account and rejects new placements until `resume`.
Malformed commands and rejected requests preserve state. Self-crossing requests
are rejected atomically. Limits conservatively count requested quantity before
execution, including IOC and FOK. Accounts can hold short inventory within limits;
cash is a signed accounting balance, not a collateral or margin model. JSON cash
balances are decimal strings to preserve exact int64 values in clients.

Run all tests, real-process protocol checks and repeated multi-seed simulation with:

```
bash scripts/stress.sh
STRESS_SEEDS=40 STRESS_EVENTS=100000 bash scripts/stress.sh
```

Every scenario transition checks book and account invariants. Each seed runs twice
and must produce identical JSON. Any command failure, invariant violation, timeout,
or nondeterminism exits nonzero. Fix the failing seed or test, add a regression test,
and rerun the gate. The script does not conceal failures by retrying unchanged code.
Use `DUNE_BUILD_DIR=_build_runtime` for isolated concurrent builds.

`dune exec exchange-async-worker` implements the same line protocol using Jane
Street Async v0.17.0 for nonblocking input/output. It applies one deterministic
state transition at a time and waits for the response to flush before reading the
next command. EOF returns the final state and terminates cleanly. Quotes come from
an Incremental v0.17.0 graph: a book variable feeds a derived quote observer with
structural cutoff. Deep-book changes that leave the top quote unchanged do not
advance the observer revision. Batched input changes can be stabilized together.
Observers are explicitly released when the adapter exits.

The adapter library is separate from the pure core. The `runtest` gate verifies
reactive cutoff, batching and observer lifecycle, compares asynchronous responses
with the synchronous protocol, confirms responses flush before EOF, and streams
15,000 commands through real subprocesses. Both workers are single-instrument,
in-memory research interfaces; neither persists Risk requests in the Engine event
journal. Async and Incremental use OCaml 5.1 or later and are declared package
dependencies. Python 3 is used by subprocess and stress tests.
