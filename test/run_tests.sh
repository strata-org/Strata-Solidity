#!/bin/bash
# Golden-file test runner for StrataSolidity.
#
# Verifies each test/examples/<name>.sol and compares the result with
# test/expected/<name>.expected (and test/expected/<name>.warnings).
#
# What is compared:
#   - the verdict of every obligation, one per line, as
#     `<verdict> <line>: <description>` (✅ proven, ❌ refuted, ❓ unknown,
#     ⚠️ verification error), sorted by line and description so that the
#     comparison does not depend on the order obligations are reported in;
#   - the totals line;
#   - translation failures (`Exception: …`, `uncaught exception: …`) and the
#     first line of each internal `BUG:` diagnostic, from stderr;
#   - separately, the `warning:` lines (unverified annotations) from stderr.
# Counterexample values are not compared: they depend on the solver.
#
# Intended outcomes: a comment line in a fixture that starts with
# `// Passes`, `// Fails`, `// Refuted` or `// Not proven` states what the
# obligations below it, up to the next such comment, must report:
#   Passes      at least one obligation, all ✅
#   Refuted     at least one ❌
#   Fails       at least one obligation that is not ✅
#   Not proven  at least one obligation that is not ✅
# A fixture whose results contradict its own comments fails, even when the
# results match the golden file.
#
# Usage:
#   test/run_tests.sh [timeout]           compare (default timeout 15 s)
#   UPDATE=1 test/run_tests.sh [timeout]  rewrite every golden file
#
# A fixture with no golden file gets one written locally (review it before
# committing). Under CI (the `CI` environment variable is set, as on
# GitHub Actions) a missing golden file is a failure instead, so that no
# fixture runs unchecked.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Precondition: Strata submodule must be initialized at ./Strata (REQ-STRATA-001,
# REQ-STRATA-005). Runs at the top so the test harness aborts with a friendly
# message before any test case invokes strata-verify.sh.
bash "$SCRIPT_DIR/../scripts/check-strata.sh"

EXAMPLES_DIR="$SCRIPT_DIR/examples"
EXPECTED_DIR="$SCRIPT_DIR/expected"
STRATA_VERIFY="${STRATA_VERIFY:-$(dirname "$SCRIPT_DIR")/Tools/Solidity/scripts/strata-verify.sh}"
TIMEOUT="${1:-15}"
UPDATE="${UPDATE:-}"
IN_CI="${CI:-}"

pass=0; fail=0; update=0

out_file=$(mktemp); err_file=$(mktemp)
trap 'rm -f "$out_file" "$err_file"' EXIT

TAB=$(printf '\t')

# The comparable result of one run: per-obligation verdicts, the totals
# line, then translation failures and BUG diagnostics. $1 = stdout, $2 = stderr.
results() {
    # Section headers (`✅ Passed (3):`) set the verdict of the obligation
    # lines that follow (`  <description> at line L, col C`). Counterexample
    # and error-message lines are indented further, and are skipped.
    LC_ALL=C awk -v tab="$TAB" '
        /^(✅|❌|❓|⚠)/ && / \([0-9]+\):$/ { mark = $1; next }
        /^[0-9]+ passed, [0-9]+ failed/ { mark = ""; next }
        mark != "" && /^  [^ ]/ {
            desc = substr($0, 3); line = "?"
            if (match(desc, / at line [0-9]+, col [0-9]+$/)) {
                line = substr(desc, RSTART + 9)
                sub(/,.*/, "", line)
                desc = substr(desc, 1, RSTART - 1)
            }
            print (line == "?" ? 0 : line) tab desc tab mark tab line
        }' "$1" |
        LC_ALL=C sort -t "$TAB" -k1,1n -k2,2 -k3,3 |
        LC_ALL=C awk -F "$TAB" '{ print $3 " " $4 ": " $2 }'
    grep -E '^[0-9]+ passed, [0-9]+ failed' "$1" || true
    # Directories stripped, so the result does not depend on the checkout.
    grep -E '^(Exception|uncaught exception|BUG): ' "$2" |
        sed -E 's|[^ ]*/([^/ ]+\.sol)|\1|g' || true
}

# Contradictions between a fixture's intended-outcome comments and its
# verdicts, one per line (nothing if none). $1 = fixture, $2 = verdict lines.
contradictions() {
    LC_ALL=C awk '
        FNR == NR {
            if (match($0, /^[ \t]*\/\/[ \t]*(Passes|Fails|Refuted|Not proven)([^A-Za-z]|$)/)) {
                kind = substr($0, RSTART, RLENGTH)
                sub(/^[ \t]*\/\/[ \t]*/, "", kind); sub(/[^A-Za-z ]$/, "", kind)
                sub(/ $/, "", kind)
                n++; at[n] = FNR; what[n] = kind
            }
            last = FNR; next
        }
        {
            # `<verdict> <line>: <description>`
            line = $2; sub(/:$/, "", line)
            if (line !~ /^[0-9]+$/) next
            m++; vline[m] = line + 0; verdict[m] = $1
        }
        END {
            at[n + 1] = last + 1
            for (i = 1; i <= n; i++) {
                total = 0; proven = 0; refuted = 0
                for (j = 1; j <= m; j++) {
                    if (vline[j] < at[i] || vline[j] >= at[i + 1]) continue
                    total++
                    if (verdict[j] == "✅") proven++
                    if (verdict[j] == "❌") refuted++
                }
                ok = 1
                if (what[i] == "Passes") ok = (total > 0 && proven == total)
                else if (what[i] == "Refuted") ok = (refuted > 0)
                else ok = (total > proven)
                if (!ok)
                    printf "  line %d says \"%s\", but lines %d-%d report %d obligation(s): %d proven, %d refuted, %d other\n",
                        at[i], what[i], at[i], at[i + 1] - 1, total, proven, refuted, total - proven - refuted
            }
        }' "$1" <(printf '%s\n' "$2")
}

for sol in "$EXAMPLES_DIR"/*.sol; do
    name=$(basename "$sol" .sol)
    expected="$EXPECTED_DIR/$name.expected"
    expected_warnings="$EXPECTED_DIR/$name.warnings"

    # Extra command-line flags for a fixture, from `<name>.flags` if present.
    flags=""
    if [ -f "$EXAMPLES_DIR/$name.flags" ]; then flags=$(cat "$EXAMPLES_DIR/$name.flags"); fi
    # shellcheck disable=SC2086
    bash "$STRATA_VERIFY" "$sol" --timeout="$TIMEOUT" $flags >"$out_file" 2>"$err_file" || true
    actual=$(results "$out_file" "$err_file")
    # Warnings about unverified annotations (stderr), with the directory
    # stripped from the `<path>:<line>:<col>:` prefix.
    actual_warnings=$(grep ': warning: ' "$err_file" | sed -E 's|^[^ ]*/([^/ ]+\.sol:)|\1|' || true)

    ok=1

    # The fixture's own statement of what it expects.
    wrong=$(contradictions "$sol" "$actual")
    if [ -n "$wrong" ]; then
        echo "❌ $name (intended outcomes)"
        echo "$wrong"
        ok=0
    fi

    # Golden warnings: compared when the file exists; written when a fixture
    # first produces warnings (a failure under CI).
    if [ -n "$UPDATE" ] && { [ -n "$actual_warnings" ] || [ -f "$expected_warnings" ]; }; then
        if [ -n "$actual_warnings" ]; then echo "$actual_warnings" > "$expected_warnings"
        else rm -f "$expected_warnings"; fi
    elif [ -f "$expected_warnings" ]; then
        if [ "$actual_warnings" != "$(cat "$expected_warnings")" ]; then
            echo "❌ $name (warnings)"
            diff <(cat "$expected_warnings") <(echo "$actual_warnings") || true
            ok=0
        fi
    elif [ -n "$actual_warnings" ]; then
        if [ -n "$IN_CI" ]; then
            echo "❌ $name: warnings with no test/expected/$name.warnings (run test/run_tests.sh locally and commit it)"
            echo "$actual_warnings"
            ok=0
        else
            echo "$actual_warnings" > "$expected_warnings"
            echo "📝 $name: generated expected warnings"
            update=$((update+1))
        fi
    fi

    compared=0
    if [ -n "$UPDATE" ]; then
        echo "$actual" > "$expected"
        echo "📝 $name: updated"
        update=$((update+1))
    elif [ ! -f "$expected" ]; then
        if [ -n "$IN_CI" ]; then
            echo "❌ $name: no test/expected/$name.expected (run test/run_tests.sh locally and commit it)"
            ok=0
        else
            echo "$actual" > "$expected"
            echo "📝 $name: generated expected output"
            update=$((update+1))
        fi
    elif [ "$actual" != "$(cat "$expected")" ]; then
        echo "❌ $name"
        diff <(cat "$expected") <(echo "$actual") || true
        ok=0
    else
        compared=1
    fi

    # Use $((var+1)), not ((var++)): the post-increment form returns exit
    # status 1 when the variable is 0, which aborts the harness under `set -e`.
    if [ "$ok" -eq 1 ]; then
        [ "$compared" -eq 1 ] && echo "✅ $name"
        pass=$((pass+1))
    else
        fail=$((fail+1))
    fi
done

echo ""
echo "$pass passed, $fail failed, $update generated"

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
