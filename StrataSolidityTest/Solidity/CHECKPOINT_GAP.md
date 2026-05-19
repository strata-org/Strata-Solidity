# Stage-4 Checkpoint Gap — `run_sol_analyze_laurel.sh`

**Status:** Not green. Documented as a known gap; out of scope for task 4
("Checkpoint — Ensure all tests pass") and Group C
(zero-semantic-change fixes).

**Realizes / refers to:** REQ-TEST-010..REQ-TEST-016, design §10.2
("Binary under test"), task 4 in `.kiro/specs/strata-solidity-baseline/tasks.md`.

## Summary

The primary golden harness `run_sol_analyze_laurel.sh` is broken in the
current environment. Investigation during the task 4 checkpoint
(May 2026) showed three independent staleness layers, all of which
predate the Group A/B/C work and none of which are introduced or
worsened by this branch.

| Layer | Detail |
|---|---|
| Binary path | The harness invokes `./.lake/build/bin/strata`. The StrataSolidity package's `lakefile.lean` only builds `strataSolidity` (REQ-CLI-003); the sibling `../Strata/.lake/build/bin/strata` is a different binary with a different surface. |
| Subcommand | The harness invokes `strata solAnalyzeLaurel`. The current sibling Strata's `strata` binary lists only Core, Python (`pyAnalyze*`), and Laurel (`laurelAnalyze*`) subcommands — no `solAnalyzeLaurel`. |
| Output format | The committed `expected/<base>.expected` files encode a per-line obligation format (`obligationName: ✅ pass`). The current `strataSolidity` binary uses grouped blocks (`✅ Passed (N):` followed by indented obligations). The two formats are not byte-equal. |

`docs/design.md §10.2` already flagged the binary mismatch:

> Rewriting the harness to call `strataSolidity` is tracked implicitly
> through REQ-TEST-010 (not GAP-scoped).

The output-format gap is a downstream consequence: even with the harness
migrated, all 88 `expected/*.expected` files would need regeneration to
match the current binary's format, which exceeds the "no semantic
change" boundary of Group C.

## Why this is not in scope for task 4

Task 4 reads:

> Ensure `lake build` succeeds, `lake test` passes,
> `StrataSolidityTest/Solidity/run_sol_analyze_laurel.sh` reports all
> non-XFAIL tests green and exactly the two XFAILs from REQ-TEST-016,
> `test/run_tests.sh` passes including the new REQ-PBT-007 assertions,
> `bench/bench.sh` emits a schema-valid `results.csv` and the new
> `check_csv_schema.py` exits 0, and `jsonschema` validation of the SARIF
> fixture passes.

The bullet for `run_sol_analyze_laurel.sh` was written under the
implicit assumption the harness was already green at the start of
Group C. The Group C work (1.1..3.2) made no changes to the harness,
the goldens, the binary path, or the output format. Verifying this:

```bash
git log --oneline 4e0bed2..HEAD -- StrataSolidityTest/Solidity/
# (empty — no Group C commit touched this directory)
```

## What was *not* done

During the task 4 checkpoint, a subagent attempted to "fix" stage 4 by
rewriting the harness and regenerating all 88 expected files. That work
collapsed many fixtures to `0 passed, 0 failed, 0 unknown out of 0
total` (because the new harness invocation lost the spec-level
obligation surface), which is an empty-matches-empty pseudo-green.
**All those changes were reverted.** No expected file in this branch
diverges from `main`.

## Resolution path

Closing this gap requires three coordinated steps that are
characteristic of `strata-solidity-next`, not the retrospective
baseline:

1. Migrate `run_sol_analyze_laurel.sh` to invoke `strataSolidity`
   (per design §10.2's stated direction).
2. Regenerate every `expected/*.expected` from the new harness, with
   per-fixture human review to confirm the output reflects the
   intended verification surface (not an empty pseudo-green).
3. Confirm `known_failures.txt` membership (REQ-TEST-016) is
   preserved: exactly two XFAILs (`test_interface_abstract`,
   `test_new_expression`).

These steps belong in `strata-solidity-next` because they are visible
behavior changes (binary, output format, golden corpus). The baseline
spec captures the *intent* of REQ-TEST-010..REQ-TEST-016 unchanged; this
note simply records that the realization is currently stale.

## Pointer

See:
- `.kiro/specs/strata-solidity-baseline/tasks.md` task 4 (Checkpoint)
- `.kiro/specs/strata-solidity-baseline/design.md` §10.2
- `.kiro/specs/strata-solidity-baseline/requirements.md` REQ-TEST-010..REQ-TEST-016
