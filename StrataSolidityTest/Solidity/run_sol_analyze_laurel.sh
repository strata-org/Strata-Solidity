#!/bin/bash
# Copyright Strata Contributors
#
#  SPDX-License-Identifier: Apache-2.0 OR MIT
#
# Run Solidity → Laurel → Core → SMT verification tests.
# Usage: ./run_sol_analyze_laurel.sh
#
# For each tests/test_*.sol file with a matching expected/*.expected file,
# the script:
#   1. Invokes solc + solast.py to produce an Ion file
#   2. Runs `strata solAnalyzeLaurel` on the Ion file
#   3. Diffs the output against expected/*.expected
#
# Tests listed in known_failures.txt are treated as XFAIL: a failure is
# expected and reported as "XFAIL", while an unexpected pass is "XPASS".

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"
EXPECTED_DIR="$SCRIPT_DIR/expected"
KNOWN_FAILURES="$SCRIPT_DIR/known_failures.txt"
TOOLS_SOL="$REPO_ROOT/Tools/Solidity"
DIALECT_DIR="$TOOLS_SOL/dialects"

passed=0
failed=0
xfailed=0
xpassed=0
skipped=0

# Load known failures into an associative array
declare -A xfail_set
if [ -f "$KNOWN_FAILURES" ]; then
    while IFS= read -r line; do
        line="${line%%#*}"          # strip comments
        line="$(echo "$line" | xargs)"  # trim whitespace
        [ -z "$line" ] && continue
        xfail_set["$line"]=1
    done < "$KNOWN_FAILURES"
fi

is_xfail() {
    [ "${xfail_set[$1]+_}" ]
}

# Ensure strata binary is built
if ! (cd "$REPO_ROOT" && lake exe strata --help > /dev/null 2>&1); then
    echo "ERROR: could not run 'lake exe strata --help'. Build first with 'lake build'."
    exit 1
fi

# Ensure dialect is generated
if [ ! -f "$DIALECT_DIR/Solidity.dialect.st.ion" ]; then
    echo "Generating Solidity dialect..."
    (cd "$TOOLS_SOL" && python3 -m src.solast dialect "$DIALECT_DIR") || {
        echo "ERROR: failed to generate Solidity dialect."
        exit 1
    }
fi

for test_file in "$TESTS_DIR"/test_*.sol; do
    [ -f "$test_file" ] || continue
    base_name=$(basename "$test_file" .sol)
    expected_file="$EXPECTED_DIR/${base_name}.expected"

    # Skip if no expected file yet
    if [ ! -f "$expected_file" ]; then
        echo "SKIP (no expected file): $base_name"
        skipped=$((skipped + 1))
        continue
    fi

    # Stage 1: solc + solast.py → Ion
    ion_file="$TESTS_DIR/${base_name}.solidity.st.ion"
    if ! (cd "$TOOLS_SOL" && python3 -m src.solast sol_to_strata \
            --dialect "$DIALECT_DIR/Solidity.dialect.st.ion" \
            "$test_file" "$ion_file"); then
        if is_xfail "$base_name"; then
            echo "XFAIL: $base_name (solc/parser failure)"
            xfailed=$((xfailed + 1))
        else
            echo "FAIL:  $base_name (solc/parser failure)"
            failed=$((failed + 1))
        fi
        continue
    fi

    # Stage 2: Run full verification pipeline via solAnalyzeLaurel
    # Post-processing pipeline:
    #   1. grep -v: remove noisy internal lines (backtraces, lake paths, etc.)
    #   2. First sed: collapse consecutive blank lines
    #   3. Second sed: normalize Lean source locations (Module:123:45 → Module:*:*)
    #      to prevent unrelated Lean edits from breaking snapshots
    #   4. Third sed: normalize compiler-generated uniqueId values
    #      (uniqueId := some 42 → uniqueId := some <id>) to prevent
    #      unrelated pipeline changes from breaking snapshots
    #   5. awk: strip multi-line AST dumps that follow "getType called on" PANIC
    #      messages; these are internal debug output, not meaningful test specs
    output=$(cd "$REPO_ROOT" && ./.lake/build/bin/strata solAnalyzeLaurel \
        "$ion_file" 2>&1 \
        | grep -v "getNameFromMd\|^backtrace:\|^\.\./\|^\./.lake/\|^/lib\|addPathCondition.*Label clash" \
        | sed '/^$/N;/^\n$/d' \
        | sed -E 's/([A-Za-z_][A-Za-z0-9_.]*):([0-9]+):([0-9]+)/\1:*:*/g' \
        | sed -E 's/uniqueId := some [0-9]+/uniqueId := some <id>/g' \
        | awk '/^PANIC.*getType called on/{print; skip=1; next} /^[^ ]/{skip=0} skip{next} {print}')
    run_rc=${PIPESTATUS[0]}

    if [ $run_rc -ne 0 ]; then
        output="error: $output"
    fi

    if ! echo "$output" | diff <(grep -v '^#' "$expected_file") - > /dev/null 2>&1; then
        if is_xfail "$base_name"; then
            echo "XFAIL: $base_name"
            xfailed=$((xfailed + 1))
        else
            echo "FAIL:  $base_name"
            echo "$output" | diff <(grep -v '^#' "$expected_file") - || true
            failed=$((failed + 1))
        fi
    else
        if is_xfail "$base_name"; then
            echo "XPASS: $base_name (unexpected pass — remove from known_failures.txt)"
            xpassed=$((xpassed + 1))
        else
            echo "PASS:  $base_name"
            passed=$((passed + 1))
        fi
    fi
done

# Clean up generated Ion files
rm -f "$TESTS_DIR"/*.solidity.st.ion

echo ""
echo "Results: $passed passed, $failed failed, $xfailed xfail, $xpassed xpass, $skipped skipped"

# Fail if any test failed, any unexpected pass, or no tests actually ran.
actual_ran=$((passed + xfailed))
if [ "$failed" -ne 0 ] || [ "$xpassed" -ne 0 ]; then
    exit 1
elif [ "$actual_ran" -eq 0 ]; then
    echo "ERROR: no tests actually ran (all skipped). Add expected files or test cases."
    exit 1
fi
