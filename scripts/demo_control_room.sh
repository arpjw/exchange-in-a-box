#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
dune exec --build-dir "${DUNE_BUILD_DIR:-_build}" exchange-control-room -- --batch --accounts 3 <<'COMMANDS'
status
place 0 1 buy 9999 100 gtc
place 1 2 sell 10001 100 post
book
place 2 3 buy 10001 25 ioc
accounts
quote
scenario 42 1000 8 250
halt 0
book
resume 0
status
quit
COMMANDS
