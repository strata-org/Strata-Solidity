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
#   1. Invokes solc + solast.py to produce an Ion file  (TODO — stub)
#   2. Runs `strata solAnalyzeLaurel` on the Ion file   (TODO — stub)
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

    # --- Pipeline stages (stubs — will be filled in later tasks) ---
    # Stage 1: solc + solast.py → Ion
    # ion_file="$TESTS_DIR/${base_name}.solidity.st.ion"
    # python3 "$REPO_ROOT/Tools/Solidity/src/solast.py" sol_to_strata \
    #     "$test_file" "$ion_file"

    # Stage 2: strata solAnalyzeLaurel → verification output
    # output=$(cd "$REPO_ROOT" && ./.lake/build/bin/strata solAnalyzeLaurel "$ion_file")

    output="(pipeline not yet wired)"

    if ! echo "$output" | diff -q "$expected_file" - > /dev/null 2>&1; then
        if is_xfail "$base_name"; then
            echo "XFAIL: $base_name"
            xfailed=$((xfailed + 1))
        else
            echo "FAIL:  $base_name"
            echo "$output" | diff "$expected_file" - || true
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
