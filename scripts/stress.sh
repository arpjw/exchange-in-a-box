#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir="${DUNE_BUILD_DIR:-_build}"
dune build --build-dir "$build_dir" @all
dune runtest --build-dir "$build_dir" --force
python3 scripts/stress.py "$build_dir/default/bin/scenario_cli.exe" "${STRESS_SEEDS:-12}" "${STRESS_EVENTS:-20000}"
