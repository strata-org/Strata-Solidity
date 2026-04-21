#!/bin/bash
# Golden-file test runner for StrataSolidity
# Runs verification on each .sol file in test/examples/ and compares output
# against expected results in test/expected/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
[ "$fail" -eq 0 ]
