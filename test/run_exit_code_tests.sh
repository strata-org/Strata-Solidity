#!/bin/bash
# Exit-code contract sub-stage for run_tests.sh (REQ-PBT-007).
#
# Validates the StrataSolidity_Binary's exit-code contract by observation
# rather than by grepping the summary line:
#   * REQ-CLI-050 — any VC outcome `fail` or `implementationError` ⇒ exit 1.
#   * REQ-CLI-051 — every VC outcome `pass` or `unknown`            ⇒ exit 0.
#   * REQ-CLI-052 — `unknown` alone is NOT a failing exit code (GAP-001).
#
# The sub-stage runs `$STRATA_VERIFY` against three curated fixtures:
#   1. A fixture with an expected `fail` (REQ-CLI-050, exit 1).
#   2. A fixture whose outcomes are only `pass` + `unknown` (REQ-CLI-051/052,
#      exit 0).
#   3. A fixture whose outcomes are all `pass` (REQ-CLI-051, exit 0).
#
# It asserts the observed exit code against the expected exit code and emits
# a PASS/FAIL line per fixture plus a final summary. The script exits 1 if any
# fixture mismatches, and 0 otherwise.
#
# This sub-stage does not modify how existing test/examples fixtures are run;
# it only adds new assertions. It honors the same $STRATA_VERIFY and timeout
# conventions as run_tests.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STRATA_VERIFY="${STRATA_VERIFY:-$PROJECT_DIR/Tools/Solidity/scripts/strata-verify.sh}"
TIMEOUT="${1:-15}"

# Three curated fixtures: (fixture_path, expected_exit_code, description).
#
# - test_assert_fail.sol: `assert(c == a)` after `c := a + b` fails when b != 0,
#   producing an `Outcome.fail` ⇒ expected exit 1 (REQ-CLI-050).
# - loop_invariant.sol: `loop-invariant totalSupply == old(totalSupply) + i`
#   produces `pass` + `unknown` (SMT times out on the inductive step, GAP-001)
#   ⇒ expected exit 0 (REQ-CLI-051, REQ-CLI-052).
# - b1_trivial.sol: trivial `ensures x == val` — all obligations pass
#   ⇒ expected exit 0 (REQ-CLI-051).
FIXTURES=(
  "$PROJECT_DIR/StrataSolidityTest/Solidity/tests/test_assert_fail.sol|1|fail  (REQ-CLI-050)"
  "$SCRIPT_DIR/examples/loop_invariant.sol|0|pass+unknown (REQ-CLI-051/052)"
  "$SCRIPT_DIR/examples/b1_trivial.sol|0|all pass (REQ-CLI-051)"
)

echo "---- Exit-code contract sub-stage (REQ-PBT-007) ----"

pass=0
fail=0
for entry in "${FIXTURES[@]}"; do
  IFS='|' read -r sol expected_code label <<<"$entry"
  name=$(basename "$sol")

  if [ ! -f "$sol" ]; then
    echo "❌ $name [$label]: fixture not found at $sol"
    fail=$((fail + 1))
    continue
  fi

  bash "$STRATA_VERIFY" "$sol" --timeout="$TIMEOUT" >/dev/null 2>&1
  actual_code=$?

  if [ "$actual_code" -eq "$expected_code" ]; then
    echo "✅ $name [$label]: exit=$actual_code (expected $expected_code)"
    pass=$((pass + 1))
  else
    echo "❌ $name [$label]: exit=$actual_code (expected $expected_code)"
    fail=$((fail + 1))
  fi
done

echo ""
echo "Exit-code contract: $pass passed, $fail failed"

[ "$fail" -eq 0 ]
