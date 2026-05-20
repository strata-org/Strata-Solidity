# PBT Evidence — REQ-PBT-003 (Golden-test stability)

This note closes **REQ-PBT-003** from
[`.kiro/specs/strata-solidity-baseline/requirements.md`](../../.kiro/specs/strata-solidity-baseline/requirements.md)
§13 without adding a second harness. REQ-PBT-003 says:

> WHEN any non-XFAIL `tests/test_*.sol` is run through the `Golden_Harness`,
> THE normalized output SHALL equal the committed `expected/<base>.expected`.

That contract is already realized, byte-for-byte, by the existing harness
[`run_sol_analyze_laurel.sh`](run_sol_analyze_laurel.sh). This file maps
each clause of REQ-PBT-003 to the specific shell lines that enforce it, and
shows how those lines also realize **REQ-TEST-011**, **REQ-TEST-012**, and
**REQ-TEST-014** from `requirements.md` §12.

Line numbers below refer to `run_sol_analyze_laurel.sh` in this directory.

## 1. REQ-TEST-011 — "iterate every `tests/test_*.sol`, produce Ion, run `solAnalyzeLaurel`, diff against `expected/<base>.expected`"

| Clause | Shell evidence |
| --- | --- |
| "iterate every `tests/test_*.sol`" | line 64 — `for test_file in "$TESTS_DIR"/test_*.sol; do` |
| resolve matching expected file | line 67 — `expected_file="$EXPECTED_DIR/${base_name}.expected"` |
| "produce an Ion file via `solast sol_to_strata`" | lines 78–80 — `python3 -m src.solast sol_to_strata --dialect ... "$test_file" "$ion_file"` |
| "run `./.lake/build/bin/strata solAnalyzeLaurel`" | lines 102–103 — `./.lake/build/bin/strata solAnalyzeLaurel "$ion_file" 2>&1 ...` |
| **"diff the normalized output against `expected/<base>.expected`"** | line 115 — `echo "$output" \| diff <(grep -v '^#' "$expected_file") - > /dev/null 2>&1` |

The `diff` at line 115 is a **byte-equal** comparison (no flags like `-w` or
`-b` are passed). This is the core mechanism that realizes REQ-PBT-003: for
every non-XFAIL test the normalized harness stdout must equal the committed
expected file exactly.

Non-XFAIL selection is negative: a test base name is **non-XFAIL** iff it is
**not** present in the `xfail_set` associative array built from
`known_failures.txt` (lines 34–43) via the `is_xfail` helper (lines 45–47).
The diff at line 115 runs for every test; its result is then routed through
the XFAIL gate at lines 116–131. When `is_xfail "$base_name"` is false
(i.e. the test is non-XFAIL) a diff mismatch increments `failed` (line 122),
which in turn triggers the REQ-TEST-014 exit-code-1 path below.

## 2. REQ-TEST-012 — "normalize output"

The five-stage normalization pipeline that REQ-TEST-012 mandates is
implemented verbatim at lines 104–108:

| Step | Line | What it does |
| --- | --- | --- |
| 1. Remove noisy internal lines | 104 | `grep -v "getNameFromMd\|^backtrace:\|^\.\./\|^\./.lake/\|^/lib\|addPathCondition.*Label clash"` |
| 2. Collapse consecutive blank lines | 105 | `sed '/^$/N;/^\n$/d'` |
| 3. Normalize `Module:<line>:<col>` to `Module:*:*` | 106 | `sed -E 's/([A-Za-z_][A-Za-z0-9_.]*):([0-9]+):([0-9]+)/\1:*:*/g'` |
| 4. Normalize `uniqueId := some <n>` to `uniqueId := some <id>` | 107 | `sed -E 's/uniqueId := some [0-9]+/uniqueId := some <id>/g'` |
| 5. Strip multi-line AST dumps after `PANIC ... getType called on` | 108 | `awk '/^PANIC.*getType called on/{print; skip=1; next} /^[^ ]/{skip=0} skip{next} {print}'` |

This five-stage pipeline defines what "normalized output" means in
REQ-PBT-003. The diff at line 115 compares the result of this pipeline
against the committed expected file; any drift in the pipeline or the
expected file surfaces immediately as a non-XFAIL `FAIL`.

## 3. REQ-TEST-014 — "exit 1 on `FAIL` or `XPASS`"

REQ-TEST-014 is the teeth of REQ-PBT-003: a silent diff mismatch would let
the baseline rot, so the harness must fail loudly. It does so at
lines 141–144:

```bash
# Fail if any test failed, any unexpected pass, or no tests actually ran.
actual_ran=$((passed + xfailed))
if [ "$failed" -ne 0 ] || [ "$xpassed" -ne 0 ]; then
    exit 1
```

`failed` is incremented on line 122 whenever a non-XFAIL test's normalized
output differs from its `expected/<base>.expected` file (that is, whenever
REQ-PBT-003 is violated). `xpassed` is incremented on line 127 whenever an
XFAIL test starts passing (the other direction — a test moved **into** the
REQ-PBT-003 contract without being removed from `known_failures.txt`).
Either condition causes `exit 1`, which in turn fails any CI job that runs
this harness.

## 4. REQ-TEST-010, REQ-TEST-013, REQ-TEST-015, REQ-TEST-016 — supporting context

For completeness, the remaining clauses of §12 are:

* **REQ-TEST-010** — harness path. Realized by the file itself:
  [`StrataSolidityTest/Solidity/run_sol_analyze_laurel.sh`](run_sol_analyze_laurel.sh).
* **REQ-TEST-013** — XFAIL registry membership. Realized by lines 34–43
  (load `known_failures.txt`), 45–47 (`is_xfail` helper), 81–83 and
  116–118 (XFAIL branch on failure), 125–127 (XPASS branch on unexpected
  pass).
* **REQ-TEST-015** — exit 1 when zero tests ran. Realized by lines 145–147.
* **REQ-TEST-016** — the XFAIL registry currently contains exactly two
  entries, `test_interface_abstract` and `test_new_expression`. Realized by
  the contents of [`known_failures.txt`](known_failures.txt).

## 5. Why no second harness

Adding a separate PBT driver for REQ-PBT-003 would duplicate the existing
diff-against-expected contract and create a second source of truth. The
existing harness already satisfies the acceptance criterion byte-for-byte,
so this note is the evidence artifact in place of a second test file. The
companion characterization PBT harness
[`PbtHarness.lean`](PbtHarness.lean) links back here from its module
docstring.

_Realizes: REQ-PBT-003; REQ-TEST-011, REQ-TEST-012, REQ-TEST-014
(supporting: REQ-TEST-010, REQ-TEST-013, REQ-TEST-015, REQ-TEST-016)._
