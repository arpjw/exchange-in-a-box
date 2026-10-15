#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
dune build web/bridge.bc.js
rm -f web/public/bridge.bc.js web/public/paper.pdf
cp _build/default/web/bridge.bc.js web/public/bridge.bc.js
cp paper/exchange_in_a_box.pdf web/public/paper.pdf
echo "Browser bundle and paper copied to web/public"
