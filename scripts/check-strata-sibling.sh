#!/usr/bin/env bash
# check-strata-sibling.sh — Precondition check for the ../Strata sibling path.
#
# StrataSolidity depends on a sibling Strata checkout via the Lake
# [[require]] entry `path = "../Strata"` in lakefile.toml (REQ-STRATA-001).
# This helper fails fast with a friendly message when that sibling is
# missing, so that `lake build`, `bench/bench.sh`, `test/run_tests.sh`, and
# `Tools/Solidity/scripts/strata-verify.sh` do not fail deep in the pipeline
# with an opaque toolchain error.
#
# The helper resolves `../Strata/lakefile.toml` relative to this script's
# location (the StrataSolidity repo root at `$SCRIPT_DIR/..`), not the
# caller's CWD, so it behaves identically no matter which wrapper invokes
# it.
#
# Realizes: REQ-STRATA-001, REQ-STRATA-005, REQ-SH-003..REQ-SH-005,
#           design §14.2 risk "Fragile sibling-path coupling".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STRATA_LAKEFILE="$PROJECT_DIR/../Strata/lakefile.toml"

if [ ! -f "$STRATA_LAKEFILE" ]; then
  echo "Error: expected sibling checkout at ../Strata. Clone https://github.com/strata-org/Strata as a sibling directory before running 'lake build'." >&2
  exit 1
fi
