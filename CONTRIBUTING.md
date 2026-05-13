# Contributing to StrataSolidity

Thanks for your interest in StrataSolidity. This document points you at the
materials you need to read before you open an issue or a pull request.

## Canonical specifications

StrataSolidity is specified under `.kiro/specs/`, not in the mdBook under
`docs/guide/` and not in `README.md`. The user guide is a friendly overview
(REQ-DIST-006); the spec is the contract. When the guide and the spec disagree,
the spec wins and the guide is treated as stale documentation.

The two canonical documents are:

- [`.kiro/specs/strata-solidity-baseline/requirements.md`](./.kiro/specs/strata-solidity-baseline/requirements.md) —
  the retrospective baseline. Every capability, CLI flag, annotation, output
  format, test-harness guarantee, and tracked gap on the current `main` branch
  is listed here with a stable identifier of the form `REQ-<CATEGORY>-<NNN>`
  (e.g. `REQ-SOL-025`, `REQ-CLI-050`, `REQ-SPEC-046`) or `GAP-<NNN>` for
  tracked limitations.
- [`.kiro/specs/strata-solidity-baseline/design.md`](./.kiro/specs/strata-solidity-baseline/design.md) —
  the retrospective baseline design. It describes the architecture actually
  realized in code today, cross-referenced to the `REQ-*` / `GAP-*` IDs. §1.1
  states that the spec (not the mdBook, not `README.md`) is the canonical
  reference.

Both files are descriptive, not prescriptive: they pin today's behavior so
that future work has something stable to diff against. Do not edit the
baseline to describe new behavior — see the next section.

## Adding new features or closing gaps

All new work lives in a follow-on spec named `strata-solidity-next`, not in
the baseline. When you propose a change:

1. **Cite the baseline.** Every new requirement in `strata-solidity-next`
   must name the `REQ-*` IDs it modifies and/or the `GAP-*` IDs it closes.
   For example, "closes `GAP-008` (dynamic-array `push`/`pop`) by extending
   `REQ-SOL-027` to model the operations" is an acceptable citation;
   "adds array support" is not.
2. **Diff against the baseline, don't rewrite it.** `strata-solidity-next`
   is the only place where `GAP-*` items may be closed. Baseline
   requirements not cited by `strata-solidity-next` must be preserved
   unchanged so that existing consumers (the IDE extension, CI scripts,
   downstream integrators) keep working.
3. **Use the stable ID scheme.** New requirements continue the existing
   prefixes: `REQ-STRATA-*`, `REQ-SOL-*`, `REQ-SPEC-*`, `REQ-PIPE-*`,
   `REQ-CLI-*`, `REQ-SH-*`, `REQ-PY-*`, `REQ-OUT-*`, `REQ-TEST-*`,
   `REQ-DIST-*`, `REQ-PBT-*`, and `GAP-*`. Do not invent new categories
   without discussing it first.
4. **Link from the PR.** Your pull-request description should list the
   baseline IDs it affects. Reviewers use those IDs to decide whether the
   change is a bugfix (behavior described in the baseline does not match
   the code), a gap closure (listed in §12 of `requirements.md`), or a
   genuinely new capability (new ID in `strata-solidity-next`).

## Where else to look

- [`README.md`](./README.md) — quick-start and build prerequisites.
- [`LIMITATIONS.md`](./LIMITATIONS.md) and [`FAQ.md`](./FAQ.md) — informal
  overviews. Authoritative enumerations live in the spec (see §12 of
  `requirements.md` for the complete `GAP-*` list).
- [`STRATA_REFERENCE.md`](./STRATA_REFERENCE.md) — reference material for
  the annotation language. Examples here should match
  `requirements.md` §4 (`REQ-SPEC-*`).
- [`CHANGELOG.md`](./CHANGELOG.md) — release notes.

If something in the user guide, the README, or any other document disagrees
with `requirements.md` or `design.md`, please open an issue citing the
baseline ID so the drift can be reconciled.
