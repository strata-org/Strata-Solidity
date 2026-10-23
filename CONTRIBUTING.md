# Contributing to StrataSolidity

Thanks for your interest in StrataSolidity. This document points you at the
materials you need to read before you open an issue or a pull request.

## Canonical specifications

StrataSolidity is specified under `.kiro/specs/`, not in the mdBook under
`docs/guide/` and not in `README.md`. The user guide is a friendly overview
(REQ-DIST-006); the spec is the contract. When the guide and the spec disagree
about intended behavior, the spec wins and the guide is treated as stale
documentation. What the current binary verifies is recorded in the
capability ledger (see [below](#the-capability-ledger)), whose entries are
checked against the binary's results.

`docs/guide/src/*.md` is the single copy of the guide's content: the mdBook
build (`docs/guide/book.toml`) and the landing-page/guide site under
`docs/site/` (see [`docs/site/README.md`](./docs/site/README.md)) both render
it, so edit it in one place.

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

## The capability ledger

[`docs/capabilities.toml`](./docs/capabilities.toml) lists every feature
with its status (verified, partly verified, unknown values, not verified,
rejected, fails) and its witnesses: obligations of `test/examples/`
fixtures as their golden files report them, translation errors, warnings,
or tests. `scripts/capabilities.py` checks the witnesses against the golden
files and generates the feature tables of `LIMITATIONS.md`, `README.md`,
`FAQ.md`, the guide's supported-features and limitations pages and option
table, the next-spec's gap table, and the landing page.

When a change alters what is verified:

1. Update the fixtures and their golden files (`test/run_tests.sh`), with a
   true and a false property for what changed. A construct that is rejected
   or fails gets a `test/examples/gap_<name>.sol` fixture pinning its error.
2. Update the entry (or add one) in `docs/capabilities.toml`: its status,
   notes and witnesses. A new command-line option needs a `[[flag]]` entry.
3. Run `python3 scripts/capabilities.py` to regenerate the tables, and
   commit them with the change.

CI runs `python3 scripts/capabilities.py --check`, which fails when a
witness no longer holds, an entry's witnesses do not fit its status, a
gap's status disagrees with the entries citing it, the option or
annotation list differs from the code, or a generated table is out of date.
Edit the text between `<!-- capabilities:begin … -->` and
`<!-- capabilities:end … -->` only through the ledger.

## Branch and PR workflow

Branches are rebased onto their base, not merged with it, so that each pull
request is a linear series of commits. The repository does not enforce a
merge method; pull requests have so far been merged with merge commits,
often as a stack (a pull request based on another one's branch, retargeted
to `main` when the lower one merges). The sections below describe the
day-to-day mechanics.

### 1. Branch hygiene

One coherent change per branch. A reviewer should be able to describe the
branch in one sentence (for example, "disables the Pages workflow," or
"moves the dialect to Lean"). If you cannot, split the branch.

Naming conventions:

- `feat/<short-noun>` — new features and capability work.
- `fix/<short-noun>` — bug fixes.
- `chore/<short-noun>` — tooling, CI, dependency, and docs work that does
  not change pipeline behavior.
- `refactor/<short-noun>` — restructure with no behavior change.
- `wip/<scratch>` — branches you do not intend to push or merge.

Branch off `main`, never off another feature branch — the only exception
is **stacked PRs**, where a follow-on branch depends on a yet-unmerged
PR (see §3 below).

Stale branches make the local list unreadable. After a PR merges, delete
the local branch and prune remote-tracking branches:

```bash
git checkout main
git pull
git fetch --prune
git branch -d <merged-branch>
```

### 2. Keeping a branch current

Run this whenever `main` advances and before requesting review:

```bash
git fetch origin
git rebase origin/main
# resolve conflicts as they come up:
git add <file>
git rebase --continue
git push --force-with-lease origin <branch>
```

Three settings make rebasing the path of least resistance:

```bash
git config --global pull.rebase true       # `git pull` rebases instead of merging
git config --global rebase.autoStash true  # auto-stash dirty work before a rebase
git config --global merge.ff only          # `git merge` errors instead of producing a merge commit
```

Always force-push with `--force-with-lease`, never plain `--force`. The
lease variant fails the push if the remote tip moved since your last
fetch, which protects collaborators (and you on a different machine)
from being silently overwritten.

If a rebase goes wrong, `git rebase --abort` returns you to the state
before the rebase started.

### 3. Pull-request etiquette with rebase

This is where rebase workflows differ most from merge workflows. The
biggest reviewer-facing surprise is that force-pushing during review can
disorient them. Two rules of thumb make it painless:

**Before review starts, rebase freely.** Squash, reword, reorder, drop
commits — whatever produces a clean history. `git rebase -i origin/main`
lets you mark commits `squash`, `fixup`, `reword`, or `drop` interactively.

**During active review, prefer fixup commits over rewriting history.**
Reviewers can then see exactly what changed since their last pass, and
GitHub's review-comment threads stay anchored to their original lines.

```bash
# while addressing review comments
git commit --fixup=<commit-hash>     # creates "fixup! <subject>" commits

# right before merge:
git rebase -i --autosquash origin/main
git push --force-with-lease
```

`--autosquash` automatically reorders fixup commits next to their targets
and marks them for squashing, so the PR history ends up tidy without
manual squashing.

When you must rewrite during review (for example, to resolve a base-branch
conflict), leave a PR comment: "Rebased onto `main` to pick up X. No
content changes since your last review." Reviewers can compare the
pre/post-rebase state via the GitHub PR's commits tab.

PR descriptions should include:

- **What** — one paragraph summary.
- **How to test** — exact commands.
- **Out of scope** — what the PR explicitly does NOT do.
- **Linked specs/issues** — `Closes #N`, `Refs REQ-NEXT-SOL-001` (see
  "Adding new features or closing gaps" above for the citation rules).

If the PR ends up rebased a few times, add a short "Changelog" section at
the bottom noting the major revisions ("v2: addressed review of
`Frontend.lean` parser; v3: rebased onto `main` to pick up dialect parity
check"). Reviewers will thank you.

## Where else to look

- [`README.md`](./README.md) — quick-start and build prerequisites.
- [`LIMITATIONS.md`](./LIMITATIONS.md) — every feature with its status,
  generated from the capability ledger. The status of each baseline
  `GAP-*` is in the gap table of
  [`strata-solidity-next`](./.kiro/specs/strata-solidity-next/requirements.md).
- [`FAQ.md`](./FAQ.md) — background and comparisons with other tools.
- [`docs/guide/src/annotation_reference.md`](./docs/guide/src/annotation_reference.md) —
  the annotation language. Examples there should match `requirements.md` §4
  (`REQ-SPEC-*`) as amended by `strata-solidity-next`.
- [`CHANGELOG.md`](./CHANGELOG.md) — release notes.

If something in the user guide, the README, or any other document disagrees
with the binary, the ledger, `requirements.md` or `design.md`, please open
an issue citing the capability or baseline ID so the drift can be
reconciled.
