# Strata Upstream Migration — Gap Analysis

**Branch:** `feat/update-strata-current`
**Strata pointer:** `349b1cf4` (upstream `strata-org/Strata`, branch `main`, 2026-05-22)
**Build status:** ❌ Intentionally broken — this branch documents the migration gap, not a working state

---

## Purpose

This branch pins the `Strata` submodule directly to the latest upstream `main` (no Everton patches on top) so we can measure how far StrataSolidity has drifted from upstream Strata's APIs. The working buildable state lives on `feat/update-strata` (= upstream `8bd50217` + 5 Everton commits).

## Summary

A direct upgrade to upstream HEAD is **not a quick port**. Two layers of breakage:

1. **Lean toolchain mismatch** (1 line fix). Upstream Strata is on Lean 4.29.1; StrataSolidity pins 4.27.0.
2. **Laurel AST refactor** (~466 sites). Multiple upstream PRs reshaped the core AST types StrataSolidity translates into.

## Tier 1 — Trivial fixes (~5 minutes)

| File | Change |
|---|---|
| `lean-toolchain` | `4.27.0` → `4.29.1` |
| `StrataSolidity/ReadSolidity.lean` | Add `import Strata.DDM.Util.Ion` |

After these, `Strata` itself builds cleanly under the new toolchain (565/565 jobs).

## Tier 2 — `SarifOutput.lean` rewrite (~1 hour)

`Core.Outcome` (a sum type with `pass | fail | unknown | implementationError`) was removed by **PR #487 — "Implement two-sided verification check"**. Replaced with:

- `Core.VCOutcome` — a structure containing `satisfiabilityProperty : SMT.Result × validityProperty : SMT.Result`
- `Core.VCError` — a sum type for encoder/solver-level errors
- `Core.VCResult.outcome : Except VCError VCOutcome` (replaces the old `result : Outcome` field)

Migration: classify a `VCOutcome` into pass/fail/unknown using upstream's predicate helpers (`passAndReachable`, `alwaysFalseAndReachable`, `canBeTrueOrFalseAndIsReachable`, etc.).

## Tier 3 — Laurel AST refactor (~1.5–2 weeks)

The Laurel AST has been substantially reshaped by several upstream PRs:

| PR | Change | Sites affected in StrataSolidity |
|---|---|---|
| #852 (`393a8d27`) | `AstNode.md : MetaData` → `AstNode.source : Option FileRange` | 19 `md :=` direct constructions, 8 `defaultMetadata`, 5 `sourceRangeToMd` |
| #1028 (`312c0ba1`) | `Identifier { text }` → `Identifier { text, uniqueId, source }` | All identifier constructions need the new fields |
| #1077 (`8380aad8`) | `StmtExpr.Identifier name` → `StmtExpr.Var (var : Variable)` | **158** `.Identifier` references |
| #1024 (`20b512ae`) | `StmtExpr.Forall` / `StmtExpr.Exists` → `StmtExpr.Quantifier kind` | **54** sites |
| #1140 (`50b0e124`) | `FileRange` metadata → `Provenance` (richer source tracking) | All `getFileRange` consumers |

The helper `mkStmtExprMd` is invoked **466 times** across StrataSolidity. Even though most of those don't need to change (the helper itself absorbs the refactor), the call sites that pass identifiers, quantifiers, or source ranges all do.

## Tier 4 — Semantic redesigns

Upstream PRs that require **redesign work**, not just translation:

### PR #759 (`84ec7da1`) — Remove modifies clauses from Core

Replaces global-variable + modifies semantics with explicit `out`/`inout` parameters. Everton's frame-condition logic in `c1540dac` and `f9895a94` is built directly on the modifies system. Frame conditions need to be re-expressed.

### PR #542 (`520efc1e`) — Remove `polyOldOp`

Everton's `c1540dac` translates `Old(FieldSelect)` using `polyOldOp` from `Strata/Languages/Core/Factory.lean`. Upstream removed `polyOldOp` and now reads pre-state through `$heap_in`. The Solidity `Old` translation needs to use the new mechanism.

### PR #1140 (`50b0e124`) — Provenance type migration

`getNameFromMd`-style code that uses `getFileRange` should be migrated to `getProvenance`, which carries `Provenance.loc | Provenance.synthesized` and supports source tracking through translation passes.

## Effort estimate

| Phase | Work | Estimate |
|---|---|---|
| 1. Lean toolchain bump | Change pin; verify `plausible` dep compatibility | < 1 day |
| 2. SarifOutput rewrite | Migrate to `VCOutcome` + `VCError` | < 1 day |
| 3. Laurel AST migration | Mechanical refactor of 466+ sites: `Var` vs `Identifier`, `Quantifier` vs `Forall/Exists`, `source` vs `md` | 3–5 days |
| 4. Frame conditions redesign | Replace modifies-based logic with `out`/`inout` mechanism | 3–5 days |
| 5. `Old` translation rewrite | Use `$heap_in`-based pre-state reads | 2–3 days |
| 6. Test suite recovery | Restore all 11 golden tests; verify SARIF schema | 1–2 days |
| **Total** | | **~2–3 weeks focused** |

## Comparison vs. partial-rebase strategy

|  | Partial rebase (`feat/update-strata`) | Full upstream port (this branch) |
|---|---|---|
| Strata SHA | `11eb339e` (= `8bd50217` + 5 Everton commits) | `349b1cf4` (upstream HEAD) |
| StrataSolidity changes | None | ~466+ sites refactored |
| Status | ✅ All 11 tests pass | ❌ Build broken |
| Effort to ship | Done | 2–3 weeks |
| Goes stale | Yes — falls behind upstream daily | No — directly tracks upstream |

## Recommendation

Stay on `feat/update-strata` (partial rebase) as the working state. Schedule the full migration as a focused 2-3 week effort. Before starting:

1. Wait for upstream AST churn to settle (the AST has shifted multiple times in the past month).
2. Cherry-pick high-value individual upstream commits onto the partial rebase as targeted fixes, deferring the full port.
3. Track upstream API removals (e.g., `polyOldOp`, `Outcome`, modifies clauses) since they each force a redesign.

## Reproduction

To re-derive these findings:

```bash
# Switch to this branch
git checkout feat/update-strata-current

# Bump Lean toolchain
echo "leanprover/lean4:v4.29.1" > lean-toolchain

# Clean & rebuild
lake clean
cd Strata && lake clean && cd ..
lake build 2>&1 | tee build.log

# Inspect first wave of errors (limited to StrataSolidity files)
grep "^error: StrataSolidity" build.log
```
