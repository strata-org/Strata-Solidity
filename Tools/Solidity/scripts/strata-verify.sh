#!/usr/bin/env bash
# strata-verify: standalone Solidity verification via the Strata pipeline.
# Usage: strata-verify <file.sol> [--sarif] [--verbose]
#
# Thin wrapper around the strataSolidity binary, which invokes solc and
# parses its JSON AST directly (in-Lean frontend — no Python, no Ion).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Precondition: Strata submodule must be initialized at ./Strata
# (REQ-STRATA-001, REQ-STRATA-005).
bash "$PROJECT_DIR/scripts/check-strata.sh"

STRATA_BIN="$PROJECT_DIR/.lake/build/bin/strataSolidity"

if [ $# -lt 1 ]; then
  echo "Usage: strata-verify <file.sol> [--sarif] [--verbose]" >&2
  exit 1
fi

SOL_FILE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
shift
EXTRA_ARGS="$*"

if [ ! -f "$SOL_FILE" ]; then
  echo "Error: $SOL_FILE not found" >&2
  exit 1
fi

if [ ! -f "$STRATA_BIN" ]; then
  echo "Error: strataSolidity not built. Run 'lake build' in $PROJECT_DIR first." >&2
  exit 1
fi

# shellcheck disable=SC2086
exec "$STRATA_BIN" "$SOL_FILE" $EXTRA_ARGS
