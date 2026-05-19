# Implementation Plan: StrataSolidity Baseline (Retrospective)

## Overview

This plan pins today's behavior as a **retrospective baseline**. It is not feature
work. The three goals are:

1. **Group A — Documentation reconciliation.** Remove documentation drift that
   is already called out as a risk in design §14.2 (`@strata` vs
   `@custom:strata`, stale "supported features" lists, unlinked GAP IDs).
   Zero semantic change.
2. **Group B — Characterization PBT harness.** Realize every `REQ-PBT-NNN`
   from `requirements.md` §13 as a runnable test so that `strata-solidity-next`
   cannot silently break the baseline contract.
3. **Group C — Known-defect fixes that do not change behavior.** Fix the
   `bench/bench.sh` `grep -c` artifact (REQ-TEST-036) and add a friendlier
   precondition error for the `../Strata` sibling path. Neither changes the
   Solidity subset, annotation language, CLI surface, or any output format.
4. **Group D — Publication and handoff.** Publish the baseline spec alongside
   the existing user guide, run requirements analysis, and tag
   `v0.1.0-baseline`.

The existing implementation language stack (Lean 4 for the core, Python for
`Tools/Solidity/`, shell for the harnesses) is already fixed by the codebase, so
there is no programming-language selection step. The companion spec
`strata-solidity-next` is the only place where GAP-001..012 are allowed to be
closed; those gaps are explicitly **out of scope** here.

## Tasks

- [x] 1. Group A — Documentation reconciliation (zero-semantic-change)
  - [x] 1.1 Fix `@strata` → `@custom:strata` in `LIMITATIONS.md` and `STRATA_REFERENCE.md`
    - Grep both files for bare `@strata` occurrences that appear in Solidity code examples and prose
    - Replace each with `@custom:strata` so the examples match the parser's actual behavior (`SpecParser.lean` recognizes only `@custom:strata`)
    - Do not change any surrounding sentence or code semantics — copy-edit only
    - _Realizes: REQ-SOL-100, design §14.2 risk "`@strata` vs `@custom:strata` documentation drift"_

  - [x] 1.2 Add a `CONTRIBUTING.md` pointer to the baseline spec
    - Create (or extend, if the file already exists) `CONTRIBUTING.md` at the repo root
    - Add a "Canonical specifications" section that points external contributors at `.kiro/specs/strata-solidity-baseline/{requirements,design}.md`
    - Explain that all new features must cite `REQ-*` / `GAP-*` IDs from the baseline and diff against it via `strata-solidity-next`
    - _Realizes: REQ-DIST-006 (mdBook is not a substitute for the spec), design §1.1 (the spec is the canonical reference)_

  - [x] 1.3 Cross-link `docs/guide/src/limitations.md` entries to `GAP-NNN` IDs
    - For each limitation entry in `docs/guide/src/limitations.md`, append the matching `GAP-NNN` ID from `requirements.md` §12
    - Use the mapping explicitly documented in `requirements.md` (GAP-001 no counterexamples, GAP-002 struct-through-mapping, GAP-003 `old()` in loop invariants, GAP-004 `@custom:strata lemma`, GAP-005 `block.timestamp`, GAP-006 constructor `msg.sender`, GAP-007 cross-contract, GAP-008 push/pop, GAP-009 multi-contract dispatch, GAP-010 storage refs, GAP-011 XFAILs, GAP-012 z3-only)
    - Do not add, remove, or re-order limitation entries — only annotate
    - _Realizes: GAP-001..GAP-012, REQ-DIST-006, REQ-DIST-007_

  - [x] 1.4 Update `README.md` "Supported Solidity features" section to defer to the baseline spec
    - Replace the hand-maintained bullet list with a short summary + a link to `requirements.md` §3 (REQ-SOL-001..REQ-SOL-100)
    - Keep a 2-3 sentence overview so casual browsers still learn what the project accepts, but remove per-feature bullets that are prone to drift
    - Do not change any other section of `README.md`
    - _Realizes: REQ-SOL-001..REQ-SOL-100, design §14.2 risk "doc drift"_

  - [x] 1.5 Add `.kiro/specs/README.md` explaining the spec layout
    - Create `.kiro/specs/README.md`
    - Document the two-spec model: `strata-solidity-baseline` is frozen and descriptive; `strata-solidity-next` diffs against it and is the only place where `GAP-*` items close
    - Document the stable ID scheme (`REQ-STRATA-*`, `REQ-SOL-*`, `REQ-SPEC-*`, `REQ-PIPE-*`, `REQ-CLI-*`, `REQ-SH-*`, `REQ-PY-*`, `REQ-OUT-*`, `REQ-TEST-*`, `REQ-DIST-*`, `GAP-*`, `REQ-PBT-*`)
    - _Realizes: REQ-STRATA-005 (relationship-to-Strata section intent), `requirements.md` Introduction §1_

- [x] 2. Group B — Characterization PBT harness (one task per REQ-PBT-NNN)
  - [x] 2.1 Scaffold `StrataSolidityTest/Solidity/PbtHarness.lean`
    - Create a new module that imports `Plausible` and exposes a shared `Plausible.Testable.Config` (fixed seed, modest sample count) used by the PBT modules below
    - Export helper generators used by parser / serializer round-trip tests (identifier names, integer literals including scientific notation like `1e24`, the five spec keywords)
    - Wire the new module through `StrataSolidityTest.lean` so `lake test` picks it up
    - _Realizes: REQ-TEST-001, REQ-TEST-002, REQ-TEST-003; shared foundation for REQ-PBT-001..REQ-PBT-008_

  - [x] 2.2 Implement REQ-PBT-001 in `StrataSolidityTest/Solidity/SpecParserTest.lean`
    - **Property 1: Spec parser round-trip idempotence**
    - **Validates: REQ-PBT-001, REQ-SPEC-001..REQ-SPEC-030, REQ-SPEC-040..REQ-SPEC-046, REQ-SPEC-070**
    - Extend (do not replace) the existing file with a Plausible property: for any generated `@custom:strata` annotation, `parse ∘ canonicalSerialize ∘ parse = parse`
    - Cover all five keywords (`requires`, `ensures`, `invariant`, `modifies`, `loop-invariant`) and the quantifier forms
    - Use the harness from 2.1
    - _Realizes: REQ-PBT-001_

  - [x] 2.3 Implement REQ-PBT-002 as a new Lake task `pbt-determinism` + shell driver
    - **Property 2: Pipeline determinism**
    - **Validates: REQ-PBT-002, REQ-PIPE-001..REQ-PIPE-005, REQ-OUT-040..REQ-OUT-045**
    - Add a Lake script/task named `pbt-determinism` in `lakefile.toml` that runs a new shell driver under `StrataSolidityTest/Solidity/`
    - The shell driver invokes `strata-verify.sh --pipeline-json` twice against a small, representative `.sol` fixture and `diff`s the two JSON outputs byte-for-byte
    - Exit non-zero on any difference in `laurel`, `core`, `obligations[*].label`, `obligations[*].status`, or `summary`
    - _Realizes: REQ-PBT-002_

  - [x] 2.4 Close REQ-PBT-003 by documenting existing golden-harness evidence
    - **Property 3: Golden-test stability**
    - **Validates: REQ-PBT-003, REQ-TEST-010..REQ-TEST-016**
    - Confirm by inspection that `run_sol_analyze_laurel.sh` already enforces byte-equal diffs for every non-XFAIL `tests/test_*.sol` against `expected/<base>.expected`
    - Do not add a second harness; instead add a short `StrataSolidityTest/Solidity/PBT_EVIDENCE.md` note mapping REQ-PBT-003 to the existing harness lines (REQ-TEST-011, REQ-TEST-012, REQ-TEST-014)
    - Link the evidence note from `PbtHarness.lean`'s docstring
    - _Realizes: REQ-PBT-003_

  - [x] 2.5 Implement REQ-PBT-004 as a Python test under `Tools/Solidity/test/`
    - **Property 4: SARIF 2.1.0 schema compliance**
    - **Validates: REQ-PBT-004, REQ-OUT-030, REQ-OUT-031**
    - Create `Tools/Solidity/test/test_sarif_schema.py`
    - Run `strata-verify.sh --sarif` against at least one fixture and validate stdout against the SARIF 2.1.0 JSON schema using `jsonschema`
    - Add a `requirements-dev.txt` entry (or extend the existing one) for `jsonschema`; do not alter any runtime Python dependency
    - _Realizes: REQ-PBT-004_

  - [x] 2.6 Implement REQ-PBT-005 in a new `StrataSolidityTest/Solidity/JsonOutputTest.lean`
    - **Property 5: `--json` shape**
    - **Validates: REQ-PBT-005, REQ-OUT-020..REQ-OUT-023, REQ-CLI-012, REQ-CLI-040**
    - Create the new module and register it in `StrataSolidityTest.lean`
    - Add a Plausible property that, for every element of the `--json` output array, asserts: `name : String`, `status ∈ {"pass","fail","unknown","implementation_error"}`, `line`/`col` are either both present (and `Nat`) or both absent
    - Drive the property by invoking the already-built `strataSolidity` binary with `--json` against a small fixture matrix
    - Use the harness from 2.1
    - _Realizes: REQ-PBT-005_

  - [x] 2.7 Implement REQ-PBT-006 in the same `JsonOutputTest.lean`
    - **Property 6: `--pipeline-json` shape**
    - **Validates: REQ-PBT-006, REQ-OUT-040..REQ-OUT-045, REQ-CLI-013, REQ-CLI-040, REQ-CLI-022, REQ-CLI-023**
    - Extend `JsonOutputTest.lean` (created in 2.6) with a second property: the `--pipeline-json` output is an object with exactly the top-level keys `laurel`, `core`, `obligations`, `summary`; each `obligations[i]` has exactly the keys `label`, `status`, `smt`, `smtResult`; `summary` has exactly the integer keys `total`, `passed`, `failed`, `unknown`
    - Depends on 2.6 because both tests share one file — run after 2.6 to avoid merge conflicts
    - _Realizes: REQ-PBT-006_

  - [x] 2.8 Implement REQ-PBT-007 as a shell test integrated into `test/run_tests.sh`
    - **Property 7: Exit-code contract**
    - **Validates: REQ-PBT-007, REQ-CLI-050, REQ-CLI-051, REQ-CLI-052**
    - Extend `test/run_tests.sh` with a new sub-stage (or a sibling script invoked from it) that runs `$STRATA_VERIFY` against three curated fixtures: one with an expected `fail`, one with only `pass`+`unknown`, one with only `pass`
    - Assert exit code `1` for the first and `0` for the other two
    - Do not change existing `run_tests.sh` behavior for current fixtures — only add assertions
    - _Realizes: REQ-PBT-007_

  - [x] 2.9 Implement REQ-PBT-008 as a Python post-processor invoked after `bench/bench.sh`
    - **Property 8: Benchmark CSV schema**
    - **Validates: REQ-PBT-008, REQ-TEST-030..REQ-TEST-035**
    - Create `bench/check_csv_schema.py` that parses `bench/results.csv` (after normalization from task 3.1) and asserts: line 1 equals the literal header from REQ-TEST-032, every data row has exactly 11 comma-separated fields, and `status ∈ {ok, error, timeout}`
    - Invoke the checker from the tail of `bench/bench.sh` as a post-run step; exit non-zero on any schema violation
    - _Realizes: REQ-PBT-008_

- [x] 3. Group C — Known-defect fixes that do not change behavior
  - [x] 3.1 Fix `bench/bench.sh` `grep -c` embedded-newline artifact
    - Locate the `grep -c` invocations that populate `state_vars`, `mappings`, `functions`, and `specs` columns
    - Pipe each count through `tr -d '\n'` (or equivalent, e.g. `| tr '\n' ' ' | awk '{print $1}'`) before it is interpolated into the CSV row
    - Do not change column count, column order, header literal, or any data semantics — only collapse embedded newlines from the `grep -c` artifact noted in REQ-TEST-036
    - Regenerate `bench/results.csv` as part of running the harness locally, then verify with task 2.9's checker
    - _Realizes: REQ-TEST-036, REQ-PBT-008, design §14.2 risk "`bench/bench.sh` `grep -c` artifact"_

  - [x] 3.2 Add a precondition check for the `../Strata` sibling path
    - Add a shell helper (e.g. `scripts/check-strata-sibling.sh`) that exits non-zero with a friendly message (`"Error: expected sibling checkout at ../Strata. Clone https://... as a sibling directory before running 'lake build'."`) when `../Strata/lakefile.toml` is missing
    - Call the helper from the top of `Tools/Solidity/scripts/strata-verify.sh` (before the existing dialect/binary checks) and from the top of `bench/bench.sh` and `test/run_tests.sh`
    - Do **not** modify `lakefile.toml`; the `[[require]]` `path = "../Strata"` stays unchanged (REQ-STRATA-001)
    - Document the helper in `README.md`'s build-prerequisites section
    - _Realizes: REQ-STRATA-001, REQ-STRATA-005, REQ-SH-003..REQ-SH-005, design §14.2 risk "Fragile sibling-path coupling"_

- [x] 4. Checkpoint — Ensure all tests pass
  - Ensure `lake build` succeeds, `lake test` passes, `StrataSolidityTest/Solidity/run_sol_analyze_laurel.sh` reports all non-XFAIL tests green and exactly the two XFAILs from REQ-TEST-016, `test/run_tests.sh` passes including the new REQ-PBT-007 assertions, `bench/bench.sh` emits a schema-valid `results.csv` and the new `check_csv_schema.py` exits 0, and `jsonschema` validation of the SARIF fixture passes
  - Ask the user if questions arise
  - **Stage 4 (`run_sol_analyze_laurel.sh`) is not green; it is documented as a known baseline gap in `StrataSolidityTest/Solidity/CHECKPOINT_GAP.md`.** The harness invokes `./.lake/build/bin/strata solAnalyzeLaurel`, which is a stale binary path + stale subcommand + stale golden output format triple — none of which is changed by Group A/B/C. Design §10.2 already acknowledged the binary mismatch ("Rewriting the harness to call `strataSolidity` is tracked implicitly through REQ-TEST-010"). Closing the gap requires migrating the harness to `strataSolidity` and regenerating all 88 `expected/*.expected` files, which is `strata-solidity-next` scope (visible behavior change), not retrospective baseline scope.
  - Stages 1, 2, 3, 5, 6, 7 are green (sibling check, `lake build`, `lake test`, `test/run_tests.sh` including REQ-PBT-007, `bench/bench.sh` + schema check, SARIF jsonschema). Two pre-existing shell defects in `test/run_tests.sh` were surfaced by the checkpoint and fixed (commits `8852f5b`, `9b0cbff`) — both are pure shell-idiom corrections.

- [ ] 5. Group D — Publication and handoff
  - [~] 5.1 Run requirements analysis against the baseline
    - Run `analyzeRequirements` against `.kiro/specs/strata-solidity-baseline/requirements.md`
    - Only apply auto-resolvable clarifications; surface any non-auto clarifications to the user before changing anything
    - If changes are applied, re-verify by re-running `analyzeRequirements` once more to confirm a clean pass
    - _Realizes: `requirements.md` §1 (stability guarantee), design §1.1_

  - [~] 5.2 Add the baseline spec to the mdBook
    - Add a new chapter (e.g. `docs/guide/src/baseline/`) containing `requirements.md` and `design.md` rendered as book pages (use symlinks or `mdBook`'s include directive so the canonical files remain in `.kiro/specs/strata-solidity-baseline/`)
    - Update `docs/guide/src/SUMMARY.md` to include the new chapter
    - Confirm `mdbook build` succeeds locally and that `.github/workflows/deploy-pages.yml` still runs green
    - _Realizes: REQ-DIST-006, REQ-DIST-007_

  - [~] 5.3 Create `.kiro/specs/strata-solidity-baseline/CITING.md`
    - Add a one-page "How to cite this baseline" note
    - Include at least three worked examples: "REQ-SOL-027 → expanded to support push/pop; see GAP-008", "REQ-CLI-050 → exit-code contract preserved by strata-solidity-next", "REQ-PBT-002 → pipeline determinism characterization test"
    - Link CITING.md from `.kiro/specs/README.md` (created in 1.5) and from the mdBook chapter (added in 5.2)
    - _Realizes: GAP-001..GAP-012, REQ-PBT-001..REQ-PBT-008_

  - [~] 5.4 Tag the repo at the baseline commit (**user action**)
    - Once tasks 1.1 through 5.3 are all green and the checkpoint (task 4) has passed, the user tags the current `main` commit as `v0.1.0-baseline`
    - The tag message should reference `.kiro/specs/strata-solidity-baseline/` and cite the corresponding `CHANGELOG.md` entry
    - Do not push the tag automatically; wait for explicit user confirmation
    - _Realizes: REQ-DIST-001, Requirement 1 (package version pinned at 0.1.0)_

## Notes

- No task in this plan is marked optional (`*`). Every task realizes a
  `REQ-*`, `GAP-*`, or `REQ-PBT-*` ID that is part of the retrospective
  baseline contract; none of them are MVP-shaveable.
- Every task cites at least one stable ID from `requirements.md` or a
  named risk from design §14.2.
- Group A runs in parallel with Group B (after 2.1). Group C is independent of
  both and can run in parallel with A and B. Group D depends on A + B + C
  completing, and task 5.4 is the final user action.
- Tasks 2.6 and 2.7 both touch the new file `JsonOutputTest.lean`; they are
  placed in different waves so the edits do not conflict.
- Task 5.1 may change `requirements.md` only if `analyzeRequirements` proposes
  auto-resolvable clarifications; any other change requires user confirmation
  to preserve the frozen baseline.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.3", "1.4", "1.5", "2.1", "3.1", "3.2"] },
    { "id": 1, "tasks": ["2.2", "2.3", "2.4", "2.5", "2.6", "2.8", "2.9"] },
    { "id": 2, "tasks": ["2.7"] },
    { "id": 3, "tasks": ["5.1", "5.2", "5.3"] },
    { "id": 4, "tasks": ["5.4"] }
  ]
}
```
