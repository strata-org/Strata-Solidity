#!/bin/bash
# Golden-file test runner for StrataSolidity
# Runs verification on each .sol file in test/examples/ and compares output
# against expected results in test/expected/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Precondition: sibling ../Strata checkout must exist (REQ-STRATA-001,
# REQ-STRATA-005). Runs at the top so the test harness aborts with a friendly
# message before any test case invokes strata-verify.sh.
bash "$SCRIPT_DIR/../scripts/check-strata-sibling.sh"

EXAMPLES_DIR="$SCRIPT_DIR/examples"
EXPECTED_DIR="$SCRIPT_DIR/expected"
STRATA_VERIFY="${STRATA_VERIFY:-$(dirname "$SCRIPT_DIR")/vscode-strata-solidity/bin/strata-verify.sh}"
TIMEOUT="${1:-15}"

pass=0; fail=0; skip=0; update=0

for sol in "$EXAMPLES_DIR"/*.sol; do
    name=$(basename "$sol" .sol)
    expected="$EXPECTED_DIR/$name.expected"

    # Run verification, extract just the results summary
    actual=$(bash "$STRATA_VERIFY" "$sol" --timeout="$TIMEOUT" 2>&1 | \
        grep -E "Passed|Failed|Unknown|total|passed" | \
        grep -v "PANIC\|backtrace" || true)

    if [ ! -f "$expected" ]; then
        # No expected file — generate it
        echo "$actual" > "$expected"
        echo "📝 $name: generated expected output"
        ((update++))
        continue
    fi

    expected_content=$(cat "$expected")
    if [ "$actual" = "$expected_content" ]; then
        echo "✅ $name"
        ((pass++))
    else
        echo "❌ $name"
        diff <(echo "$expected_content") <(echo "$actual") || true
        ((fail++))
    fi
done

echo ""
echo "$pass passed, $fail failed, $skip skipped, $update generated"

# -----------------------------------------------------------------------------
# Sub-stage: exit-code contract (REQ-PBT-007).
# Pins REQ-CLI-050 (fail ⇒ exit 1), REQ-CLI-051 (pass/unknown only ⇒ exit 0),
# and REQ-CLI-052 (unknown is not a failing exit code). Implemented as a
# sibling script so the golden-file logic above is unchanged.
# -----------------------------------------------------------------------------
exit_code_fail=0
if [ -x "$SCRIPT_DIR/run_exit_code_tests.sh" ]; then
    echo ""
    STRATA_VERIFY="$STRATA_VERIFY" \
        bash "$SCRIPT_DIR/run_exit_code_tests.sh" "$TIMEOUT" || exit_code_fail=1
fi

[ "$fail" -eq 0 ] && [ "$exit_code_fail" -eq 0 ]
