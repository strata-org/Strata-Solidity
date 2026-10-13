#!/bin/bash
# Golden-file test runner for StrataSolidity
# Runs verification on each .sol file in test/examples/ and compares output
# against expected results in test/expected/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Precondition: Strata submodule must be initialized at ./Strata (REQ-STRATA-001,
# REQ-STRATA-005). Runs at the top so the test harness aborts with a friendly
# message before any test case invokes strata-verify.sh.
bash "$SCRIPT_DIR/../scripts/check-strata.sh"

EXAMPLES_DIR="$SCRIPT_DIR/examples"
EXPECTED_DIR="$SCRIPT_DIR/expected"
# Default STRATA_VERIFY to the canonical wrapper at Tools/Solidity/scripts/.
# The original default (vscode-strata-solidity/bin/strata-verify.sh) referred
# to an earlier project layout that no longer exists in this repo; aligning
# with bench/bench.sh and test/run_exit_code_tests.sh which both use this
# path as their default.
STRATA_VERIFY="${STRATA_VERIFY:-$(dirname "$SCRIPT_DIR")/Tools/Solidity/scripts/strata-verify.sh}"
TIMEOUT="${1:-15}"

pass=0; fail=0; skip=0; update=0

out_file=$(mktemp); err_file=$(mktemp)
trap 'rm -f "$out_file" "$err_file"' EXIT

for sol in "$EXAMPLES_DIR"/*.sol; do
    name=$(basename "$sol" .sol)
    expected="$EXPECTED_DIR/$name.expected"
    expected_warnings="$EXPECTED_DIR/$name.warnings"

    bash "$STRATA_VERIFY" "$sol" --timeout="$TIMEOUT" >"$out_file" 2>"$err_file" || true
    # Extract just the results summary: the section headers ("✅ Passed
    # (3):") and the totals line ("3 passed, 0 failed, ..."). Anchored, so
    # obligation names and counterexample variables (`ensures totalSupply
    # ...`, `total_in@3 = 0`) do not leak into the comparison.
    actual=$(grep -E "^(✅|❌|❓) (Passed|Failures|Unknown) \(|^[0-9]+ passed, [0-9]+ failed" \
        "$out_file" || true)
    # Warnings about unverified annotations (stderr), with the directory
    # stripped from the `<path>:<line>:<col>:` prefix.
    actual_warnings=$(grep ': warning: ' "$err_file" | sed -E 's|^[^ ]*/([^/ ]+\.sol:)|\1|' || true)

    # Golden warnings: compared when the file exists, generated when a
    # fixture first produces warnings.
    if [ -f "$expected_warnings" ]; then
        if [ "$actual_warnings" != "$(cat "$expected_warnings")" ]; then
            echo "❌ $name (warnings)"
            diff <(cat "$expected_warnings") <(echo "$actual_warnings") || true
            fail=$((fail+1))
        fi
    elif [ -n "$actual_warnings" ]; then
        echo "$actual_warnings" > "$expected_warnings"
        echo "📝 $name: generated expected warnings"
        update=$((update+1))
    fi

    if [ ! -f "$expected" ]; then
        # No expected file — generate it
        echo "$actual" > "$expected"
        echo "📝 $name: generated expected output"
        # Use $((var+1)) (not ((var++))) so the increment is safe under
        # `set -e`: the post-increment form returns exit status 1 when the
        # variable is 0, which would abort the harness silently after the
        # first fixture and prevent the REQ-PBT-007 sub-stage from running.
        update=$((update+1))
        continue
    fi

    expected_content=$(cat "$expected")
    if [ "$actual" = "$expected_content" ]; then
        echo "✅ $name"
        pass=$((pass+1))
    else
        echo "❌ $name"
        diff <(echo "$expected_content") <(echo "$actual") || true
        fail=$((fail+1))
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
