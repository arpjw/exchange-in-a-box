# Local terminal control room

Start with `dune exec exchange-control-room`. Type `help` for the available
commands, and `quit` or send EOF to exit. `--accounts N` creates account IDs
0 through N-1; the default is eight. `--batch` suppresses the startup banner
and prompts for scripts.

The interface uses Async for terminal input/output and Incremental for the
quote display. Order, cancellation and account halt/resume requests use the same
pure Gateway/Risk transitions as the machine-readable workers. The account table
shows signed inventory, exact cash, halt status and configured limits. The book
shows individual orders in price/time priority. `book 20` shows up to twenty
orders per side. `status` counts submitted order/risk operations, including
rejected attempts; display commands do not increment that count.

Example session:

```
place 0 1 buy 9999 100 gtc
place 1 2 sell 10001 100 post
book
place 2 3 buy 10001 25 ioc
accounts
scenario 42 1000 8 250
halt 0
status
quit
```

`scenario SEED EVENTS [AGENTS [IMPACT_LOTS]]` runs a fresh synthetic experiment
with initial reference price 10000, prints a start message and result, then returns
to the prompt. It runs off the Async scheduler thread, and commands remain ordered:
the next command is processed after the experiment finishes. The current session's
book and account ledger stay available. Scenarios are bounded to 100000 events,
1000 agents and 1000000 impact lots. They are simulated mechanics, not calibrated
market predictions. The displayed impact cost charges only executed lots.

Run `bash scripts/demo_control_room.sh` for a fixed reproducible demonstration.
`DUNE_BUILD_DIR=_build_runtime` selects an isolated build directory when needed.
The runtime test gate exercises real subprocess prompts before EOF, order fills,
risk rejection, bounded scenario inputs, scenario isolation and identical batch
output across repeated runs. This is a local, in-memory, single-instrument
interface with no broker connectivity.
