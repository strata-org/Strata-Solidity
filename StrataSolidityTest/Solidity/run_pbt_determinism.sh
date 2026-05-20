#!/usr/bin/env bash
# Copyright Strata Contributors
#
# SPDX-License-Identifier: Apache-2.0 OR MIT
#
# Property 2: Pipeline determinism (REQ-PBT-002).
# Validates: REQ-PBT-002, REQ-PIPE-001..REQ-PIPE-005, REQ-OUT-040..REQ-OUT-045.
#
# Invokes `strata-verify.sh <fixture> --pipeline-json` twice against a small,
# representative Solidity fixture and checks that the five structural
# determinism invariants (`laurel`, `core`, `obligations[*].label`,
# `obligations[*].status`, and `summary`) are byte-equal across runs.
#
# On any difference in those five fields, the script prints the offending diff
# and exits 1. The script also performs a full byte-for-byte diff of the raw
# JSON outputs for informational evidence; any difference there is printed as
# a warning, but only differences in the five structural fields fail the run.
#
# Note — SMT field variance. The `obligations[*].smt` field embeds the
# `strata-verify.sh` temp-directory path in a `(set-info :file …)` annotation,
# which differs per run because `strata-verify.sh` calls `mktemp -d`. This is
# an incidental artifact of the shell wrapper, not a pipeline determinism
# violation, so REQ-PBT-002 deliberately excludes `smt` and `smtResult` from
# the determinism contract (see tasks.md task 2.3 and requirements.md §13).
#
# Usage:
#   StrataSolidityTest/Solidity/run_pbt_determinism.sh [fixture.sol]
#
# If no fixture is given, defaults to
# StrataSolidityTest/Solidity/tests/test_arithmetic.sol, a compact pass-only
# fixture that minimizes noise from VC status and exercises the full
# Python → Ion → Lean → Laurel → Core → SMT pipeline (REQ-PIPE-001..005).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STRATA_VERIFY="$PROJECT_DIR/Tools/Solidity/scripts/strata-verify.sh"
DEFAULT_FIXTURE="$SCRIPT_DIR/tests/test_arithmetic.sol"

FIXTURE="${1:-$DEFAULT_FIXTURE}"

if [ ! -x "$STRATA_VERIFY" ]; then
  echo "Error: $STRATA_VERIFY is not executable" >&2
  exit 2
fi

if [ ! -f "$FIXTURE" ]; then
  echo "Error: fixture $FIXTURE not found" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required to extract structural fields from --pipeline-json" >&2
  echo "       install jq (e.g. 'brew install jq' or 'apt-get install jq') and retry" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

RUN_A="$WORK_DIR/run_a.json"
RUN_B="$WORK_DIR/run_b.json"

echo "==== PBT-determinism driver (REQ-PBT-002) ===="
echo "  fixture:        $FIXTURE"
echo "  strata-verify:  $STRATA_VERIFY"
echo "  workdir:        $WORK_DIR"
echo

echo "-- Run 1/2 --"
"$STRATA_VERIFY" "$FIXTURE" --pipeline-json > "$RUN_A"
echo "-- Run 2/2 --"
"$STRATA_VERIFY" "$FIXTURE" --pipeline-json > "$RUN_B"

# -- Informational: full byte-for-byte diff of raw --pipeline-json outputs.
# Any difference here is surfaced as a warning. Only structural-field
# differences (checked below) are promoted to exit-code failure.
if cmp -s "$RUN_A" "$RUN_B"; then
  echo "[ok] raw --pipeline-json output is byte-equal across runs"
  raw_equal=1
else
  echo "[warn] raw --pipeline-json output differs across runs"
  echo "       (diff below; expected to be confined to obligations[*].smt"
  echo "        which embeds the per-run strata-verify.sh TMPDIR and is NOT"
  echo "        part of the REQ-PBT-002 determinism contract)"
  diff -u "$RUN_A" "$RUN_B" || true
  raw_equal=0
fi

# -- Hard contract (REQ-PBT-002): diff the five structural fields.
#   laurel, core, obligations[*].label, obligations[*].status, summary.
# Each field is extracted with jq, dumped into a canonical text form, and
# diffed pair-wise. Any difference exits 1.

extract () {
  # $1 = jq filter, $2 = output path
  local filter="$1"
  local out="$2"
  local src="$3"
  jq -r "$filter" "$src" > "$out"
}

fail=0

check_field () {
  local label="$1"
  local filter="$2"

  local a="$WORK_DIR/a_${label}.txt"
  local b="$WORK_DIR/b_${label}.txt"
  extract "$filter" "$a" "$RUN_A"
  extract "$filter" "$b" "$RUN_B"

  if cmp -s "$a" "$b"; then
    echo "[ok]   field '$label' is byte-equal across runs"
  else
    echo "[FAIL] field '$label' differs across runs (REQ-PBT-002)"
    diff -u "$a" "$b" || true
    fail=1
  fi
}

echo
echo "==== Structural-field checks (REQ-PBT-002) ===="

# 1. laurel (REQ-OUT-041)
check_field "laurel"  '.laurel'
# 2. core (REQ-OUT-042)
check_field "core"    '.core'
# 3. summary (REQ-OUT-045)
check_field "summary" '.summary | to_entries | sort_by(.key) | .[] | "\(.key)=\(.value)"'
# 4. obligations[*].label (REQ-OUT-043)
check_field "obligations[*].label"  '.obligations[] | .label'
# 5. obligations[*].status (REQ-OUT-043)
check_field "obligations[*].status" '.obligations[] | .status'

echo
if [ "$fail" -eq 0 ]; then
  if [ "$raw_equal" -eq 1 ]; then
    echo "PASS: pipeline determinism holds (raw byte-equal AND all 5 structural fields equal)."
  else
    echo "PASS: pipeline determinism holds for the 5 structural fields."
    echo "      (raw output differs, but only outside the REQ-PBT-002 contract — see warning above)"
  fi
  exit 0
else
  echo "FAIL: pipeline determinism violated (see [FAIL] lines above)."
  exit 1
fi
