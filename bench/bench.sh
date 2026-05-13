#!/usr/bin/env bash
# bench.sh — Run StrataSolidity benchmarks and collect performance data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFY="${STRATA_VERIFY:-$SCRIPT_DIR/../Tools/Solidity/scripts/strata-verify.sh}"
TIMEOUT="${1:-30}"
RESULTS="$SCRIPT_DIR/results.csv"

echo "benchmark,functions,specs,state_vars,mappings,status,time_ms,pass,fail,unknown,total" > "$RESULTS"

for sol in "$SCRIPT_DIR"/b*.sol; do
  name=$(basename "$sol" .sol)
  funcs=$(grep -c "function " "$sol" 2>/dev/null || echo 0)
  specs=$(grep -c "@custom:strata" "$sol" 2>/dev/null || echo 0)
  maps=$(grep -c "mapping" "$sol" 2>/dev/null || echo 0)

  printf "%-15s funcs=%-2s specs=%-2s maps=%-2s " "$name" "$funcs" "$specs" "$maps"

  start=$(python3 -c "import time; print(int(time.time()*1000))")
  output=$(bash "$VERIFY" "$sol" --timeout="$TIMEOUT" 2>&1) || true
  end=$(python3 -c "import time; print(int(time.time()*1000))")
  elapsed=$((end - start))

  summary=$(echo "$output" | grep "out of" || echo "")
  if [ -n "$summary" ]; then
    pass=$(echo "$summary" | sed -E 's/^([0-9]+) passed.*/\1/')
    fail=$(echo "$summary" | sed -E 's/.*passed, ([0-9]+) failed.*/\1/')
    unknown=$(echo "$summary" | sed -E 's/.*failed, ([0-9]+) unknown.*/\1/')
    total=$(echo "$summary" | sed -E 's/.*out of ([0-9]+) total.*/\1/')
    status="ok"
  elif echo "$output" | grep -qi "error\|panic\|exception\|FAILED"; then
    pass=0; fail=0; unknown=0; total=0; status="error"
  else
    pass=0; fail=0; unknown=0; total=0; status="timeout"
  fi

  printf "=> %-6s %5dms  %s/%s pass\n" "$status" "$elapsed" "$pass" "$total"
  echo "$name,$funcs,$specs,$maps,$status,$elapsed,$pass,$fail,$unknown,$total" >> "$RESULTS"
done

echo ""
cat "$RESULTS" | column -t -s,
echo ""
awk -F, 'NR>1 && $5=="ok" { n++; t+=$6; p+=$7; tot+=$10 }
  END { printf "OK: %d/%d | Total: %dms | Avg: %dms | Obligations: %d/%d passed\n", n+0, NR-1, t, (n>0?t/n:0), p, tot }' "$RESULTS"

# Post-run schema check (REQ-PBT-008). Runs alongside the embedded-newline fix
# from task 3.1 (REQ-TEST-036); on an unfixed CSV this exits non-zero, which
# is the intended enforcement behavior for the baseline.
python3 "$SCRIPT_DIR/check_csv_schema.py" "$RESULTS"
