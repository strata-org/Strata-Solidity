#!/usr/bin/env bash
# strata-verify: standalone Solidity verification via the Strata pipeline.
# Usage: strata-verify <file.sol> [--sarif] [--verbose]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$TOOLS_DIR/../.." && pwd)"

# Precondition: sibling ../Strata checkout must exist (REQ-STRATA-001,
# REQ-STRATA-005). Runs before the dialect/binary checks below so users
# see a friendly message before any of the REQ-SH-003..REQ-SH-005 errors.
bash "$PROJECT_DIR/scripts/check-strata-sibling.sh"

STRATA_PYTHON="$(cd "$PROJECT_DIR/../Strata/Tools/Python" 2>/dev/null && pwd || echo "")"
DIALECT="$TOOLS_DIR/dialects/Solidity.dialect.st.ion"
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

if [ ! -f "$DIALECT" ]; then
  echo "Error: Dialect not found at $DIALECT. Run gen_dialect.sh first." >&2
  exit 1
fi

if [ ! -f "$STRATA_BIN" ]; then
  echo "Error: strataSolidity not built. Run 'lake build' in $PROJECT_DIR first." >&2
  exit 1
fi

# Create temp dir for intermediate files
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

ION_FILE="$TMPDIR/$(basename "$SOL_FILE" .sol).solidity.st.ion"

# Step 1: Solidity -> Ion (via solc + solast.py)
(cd "$TOOLS_DIR" && PYTHONPATH="${STRATA_PYTHON}:${PYTHONPATH:-}" \
  python3 -m src.solast sol_to_strata \
    --dialect "$DIALECT" \
    "$SOL_FILE" \
    "$ION_FILE") \
  2>&1 || { echo "Error: Failed to parse $SOL_FILE" >&2; exit 1; }

# Step 2: Ion -> Verification (via strataSolidity)
# shellcheck disable=SC2086
"$STRATA_BIN" "$ION_FILE" $EXTRA_ARGS
