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

# Curated fixtures: (fixture_path, expected_exit_code, description[, extra_args]).
#
# - test_assert_fail.sol: `assert(c == a)` after `c := a + b` fails when b != 0,
#   producing an `Outcome.fail` ⇒ expected exit 1 (REQ-CLI-050).
# - loop_invariant.sol: `loop-invariant totalSupply == old(totalSupply) + i`
#   produces `pass` + `unknown` (SMT times out on the inductive step, GAP-001)
#   ⇒ expected exit 0 (REQ-CLI-051, REQ-CLI-052).
# - b1_trivial.sol: trivial `ensures x == val` — all obligations pass
#   ⇒ expected exit 0 (REQ-CLI-051).
# - ignored_annotations.sol: all obligations pass but annotations are not
#   verified (warned on stderr) ⇒ exit 0, and exit 1 under `--strict`.
#   The `--strict` failure must name `--strict`.
#
# An optional fourth field carries extra CLI arguments.
FIXTURES=(
  "$PROJECT_DIR/StrataSolidityTest/Solidity/tests/test_assert_fail.sol|1|fail  (REQ-CLI-050)"
  "$SCRIPT_DIR/examples/loop_invariant.sol|0|pass+unknown (REQ-CLI-051/052)"
  "$SCRIPT_DIR/examples/b1_trivial.sol|0|all pass (REQ-CLI-051)"
  "$SCRIPT_DIR/examples/ignored_annotations.sol|0|pass, ignored annotations warned"
  "$SCRIPT_DIR/examples/ignored_annotations.sol|1|ignored annotations under --strict|--strict"
)

echo "---- Exit-code contract sub-stage (REQ-PBT-007) ----"

pass=0
fail=0
for entry in "${FIXTURES[@]}"; do
  IFS='|' read -r sol expected_code label extra_args <<<"$entry"
  name=$(basename "$sol")

  if [ ! -f "$sol" ]; then
    echo "❌ $name [$label]: fixture not found at $sol"
    fail=$((fail + 1))
    continue
  fi

  # shellcheck disable=SC2086  # extra_args is intentionally word-split
  stderr=$(bash "$STRATA_VERIFY" "$sol" --timeout="$TIMEOUT" ${extra_args:-} 2>&1 >/dev/null)
  actual_code=$?
  # A --strict failure must come from --strict itself, not from a binary
  # that does not know the flag (which also exits 1, with a usage message).
  if [[ "${extra_args:-}" == *--strict* ]] && [ "$expected_code" -eq 1 ] && \
     ! grep -q '^error: --strict:' <<<"$stderr"; then
    echo "❌ $name [$label]: exit=$actual_code but no '--strict' error on stderr"
    fail=$((fail + 1))
    continue
  fi

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
