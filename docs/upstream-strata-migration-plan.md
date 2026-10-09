# Upstream Strata Migration and Improvement Plan

## Status and scope

| | Revision | Date | Lean |
|---|---|---|---|
| Previous pin | `349b1cf4915d3d9357b8de7edcc94d3b9a79f0b5` (nightly-20260523) | 2026-05-22 | v4.29.1 |
| First analysis of this document | `79c2cd6c076b31c32009c0da742b6fdc3fb5d27a` | 2026-08-26 | v4.29.1 |
| **Current pin** | `d1fc3a0835a77db7eb462eb0fd88038268fef1d8` (nightly-20261008) | 2026-10-08 | **v4.31.0** |

Delta from the previous pin to the current pin: 393 commits, 2,120 changed
paths, +222,026 / −101,878 lines. Strata-DDM resolves to `b70976b1`.

The compatibility port is **done** (branch `strata-update`). It is
behavior-preserving: across all 144 `.sol` fixtures (`test/examples`,
`StrataSolidityTest/Solidity/tests`, `bench`) the per-fixture
(pass, fail, unknown) counts and the CLI exit codes are identical to the
`349b1cf4` baseline, the golden suite passes unchanged, and `lake test`,
the PBT determinism check, SARIF schema validation and the bench CSV
schema check pass. See [Compatibility port outcome](#compatibility-port-outcome).

## Executive summary

This should not be treated as a routine submodule bump. The first migration should be a compatibility-only port that preserves StrataSolidity behavior. Once that is stable, we can adopt upstream improvements independently and measure their effect.

The highest-value opportunities are:

1. Replace synthetic pre-state parameters with native Core two-state `old` and `inout` semantics.
2. Use quantifier-free key-scoped frame conditions under array theory.
3. Adopt checked, configurable Core verification pipelines.
4. Improve SARIF and source diagnostics using upstream metadata and pipeline messages.
5. Re-evaluate struct fields through mappings against the improved heap and composite-type pipeline.
6. Simplify the frontend by emitting native Laurel exceptions, do-while loops, compound operations, and instance procedures.
7. Measure the cumulative effect of upstream Core and SMT performance work.

The compatibility port and these semantic improvements must remain separate. Combining them would make regressions difficult to diagnose.

## Upstream changes

### 1. DDM package extraction

Strata's Dialect Definition Mechanism moved from `Strata.DDM.*` into the separate `strata-org/Strata-DDM` package, imported as `StrataDDM.*`.

Examples:

- `Strata.DDM.Integration.Lean` becomes `StrataDDM.Integration.Lean`.
- `Strata.DDM.AST` becomes `StrataDDM.AST`.
- `Strata.DDM.Ion` becomes `StrataDDM.Ion`.

At the current pin Strata resolves Strata-DDM at revision `b70976b135810dc8a0c47e66e9ebd58fa93add78`. Note that the namespace also changed: `Strata.Program`/`Strata.Ann` are now `StrataDDM.Program`/`StrataDDM.Ann`.

#### Impact on StrataSolidity

Several imports no longer exist. The production `.sol` pipeline no longer requires Ion, so obsolete Ion input compatibility should probably be removed rather than ported to the new package.

### 2. Laurel module and pipeline reorganization

Two modules imported directly by StrataSolidity were removed:

- `Strata.Languages.Laurel.Laurel` was replaced by `LaurelAST` and related modules.
- `Strata.Languages.Laurel.LaurelToCoreTranslator` was replaced by the newer schema pass and compilation pipeline, principally `LaurelToCoreSchemaPass`.
- Since `c5f14dff` (2026-09-10) all of Laurel lives in a separate `StrataLaurel` library: `StrataLaurel.Implementation.LaurelAST`, `StrataLaurel.Implementation.LaurelCompilationPipeline`, …

The high-level `Strata.Laurel.translate` API remains, but its implementation, result types, diagnostics, and pass structure changed substantially. Current upstream also exposes higher-level APIs such as `verifyToVcResults`, `verifyToMergedResults`, `verifyToDiagnostics`, and `verifyToMessages`.

#### Opportunity

After compatibility is restored, evaluate whether the CLI can use a higher-level Laurel verification API instead of manually invoking translation and `Core.verify`. Custom pipeline JSON and SARIF requirements may still justify some manual orchestration.

### 3. Core verification API and checked pipelines

`Core.Verifier` was substantially rewritten. Verification now supports:

- Configurable phase pipelines
- Explicit pipeline context
- Checked phase contracts
- Shared SMT environments
- More accurate phase timing
- Cleaner separation between transformation, obligation extraction, and SMT discharge

Commit `cb760011` introduced phase contracts. Each phase can declare facts it requires, establishes, and preserves, including:

- No CFG bodies
- No remaining calls
- No loops or loop invariants
- Static single assignment
- No internal function declarations
- No polymorphic functions or procedures
- No beta redexes

Invalid phase orderings are rejected before verification.

#### Opportunity

This can improve soundness and maintainability by preventing transformations from silently skipping unsupported Core shapes. StrataSolidity could safely add frontend-specific prefix phases, expose phase timing, and provide a `--debug-pipeline` mode.

### 4. Native two-state `old` semantics

Commit `ef4582f4`, `laurel: wire old() to Core two-state semantics`, replaced synthetic heap input parameters with native Core pre-state semantics:

- State-changing parameters become true `inout` parameters.
- Pre-state reads use Core's native `old` identifiers.
- `PushOldInward` normalizes `old(complexExpression)` until `old` wraps inout variables directly.
- Call sites use `.inoutArg` rather than paired input and output arguments.

Later changes added:

- `old(...)` over file-scope globals
- Correct preservation of `old` through procedure inlining (`38115786`)
- Correct call-site substitution for renamed inout parameters

#### Opportunity

StrataSolidity currently synthesizes `<state>_in` parameters and entry assumptions. Native upstream semantics could:

- Remove synthetic pre-state parameters
- Simplify internal-call argument threading
- Reduce special cases in `SpecRewriter`
- Make generated Laurel more idiomatic
- Reuse upstream correctness fixes

This probably does not automatically solve `old()` in loop invariants. Procedure-entry pre-state and loop-entry pre-state are different concepts, so the intended annotation semantics must be defined first.

### 5. Quantifier-free frame conditions under array theory

Commit `ef14ccd1` optimized key-scoped `modifies` clauses when array theory is enabled. Instead of a universally quantified frame condition, upstream can generate a quantifier-free array equation based on `store` and `select`.

Conceptually, this replaces a formula like:

```text
forall obj, field.
  obj != modifiedObject ->
  read(oldHeap, obj, field) == read(newHeap, obj, field)
```

with an equation similar to:

```text
newHeap = store(oldHeap, modifiedObject, select(newHeap, modifiedObject))
```

#### Opportunity

This aligns with StrataSolidity's key-scoped specifications:

```solidity
/// @custom:strata modifies balances[msg.sender]
```

Potential benefits include:

- Faster SMT discharge
- Fewer quantifier instantiations
- Fewer `unknown` results
- Better mapping-heavy contract performance
- Better prospects for concrete counterexamples

StrataSolidity already exposes `--array-theory`. We must confirm that the generated mapping representation reaches the optimized upstream path, because some Solidity state is flattened before Laurel heap parameterization.

This optimization alone will not guarantee counterexamples; other mapping axioms and user quantifiers may still require model-based quantifier instantiation.

### 6. Heap and composite-object correctness

Relevant upstream changes include:

- Synthesized heap well-formedness conditions (`440e9a42`)
- Constrained types as composite fields (`877014f5`)
- Bitvectors as composite fields
- Better chained-field-access handling
- Correct hidden-state argument ordering
- Improved allocation invariants for composite inputs and outputs
- Improved heap parameterization diagnostics

#### Opportunity: struct fields through mappings

StrataSolidity's major data-model gap is accessing fields through mapping values:

```solidity
mapping(bytes32 => Payment) payments;
payments[id].amount
```

The upstream work is promising but does not conclusively close the gap. Heap well-formedness work still calls out indirectly reachable references as future work.

Run a focused spike after the compatibility port:

1. Add one minimal `mapping(K => Struct)` fixture.
2. Inspect generated Laurel before and after heap parameterization.
3. Identify whether the remaining issue lies in Solidity translation, Laurel type resolution, heap parameterization, or Core encoding.
4. Determine whether the gap can now be closed by a targeted frontend change.

### 7. Richer Laurel language support

Current Laurel added or improved:

- Native post-tested do-while loops (`d5ed9000`)
- Increment, decrement, and compound assignment
- First-class exceptions, including throw, try/catch, and contracts
- Instance procedures and inherited instance-procedure resolution (`c6d5c2fe` and later work)
- File-scope global variables
- User-level polymorphism
- Generic composites, datatypes, and type aliases
- Opaque types
- Native immutable `Set`
- Optional declaration type annotations
- Procedure calls inside specifications
- Constants with right-hand sides
- Coroutine rely/guarantee verification

#### Opportunities

**Exceptions:** map Solidity `revert`, custom errors, and `try/catch` more faithfully than path pruning or conservative approximation.

**Do-while and compound operations:** replace frontend desugaring with native Laurel constructs so upstream owns the transformation and its correctness.

**Instance procedures:** reconsider the current static-procedure-plus-explicit-`self` model. Instance procedures could support better internal calls, inheritance, override resolution, contract-instance state, and eventually modular cross-contract calls.

**Native sets:** model role membership, permission sets, and dynamic write sets using a first-class abstraction. The latest Core change encodes sets as SMT arrays `Array T Bool`.

### 8. Stronger Laurel resolution and type checking

Upstream Laurel resolution now checks:

- Boolean conditions
- Numeric arithmetic operands
- Assignment compatibility
- Procedure argument types
- Functional procedure result types
- Instance-call argument types
- Name scopes and sibling-block reuse
- Call-site type argument inference

#### Opportunity

Use Laurel type checking as an explicit frontend correctness boundary:

- Every generated fixture should pass Laurel resolution without unexpected warnings.
- Resolution warnings should fail CI unless explicitly allowlisted.
- Malformed generated Laurel should produce a frontend diagnostic at the Solidity source range rather than an obscure Core error.

### 9. Core and SMT performance improvements

Upstream contains multiple changes relevant to mapping-heavy verification:

- Shared assumption prefixes encoded once across obligations
- Shared SMT text rendered once per environment
- Buffered solver I/O
- Faster datatype lookup
- Hash-based free-variable and managed-name tracking
- Faster obligation accumulation
- Common-subexpression elimination replacing the old ANF encoder
- Function and procedure monomorphization
- Internal function lifting
- Quantifier normalization and coalescing
- Array-based set encoding
- Unified SMT identifier uniqueness
- SMT filename length limits
- Improved phase timing

#### Opportunity

After the compatibility port, rerun the benchmark suite unchanged and compare:

- Total verification time
- Per-obligation time
- SMT file size
- Number of generated quantifiers
- Pass, fail, and unknown distribution
- Peak memory
- ERC20 and nested-mapping behavior

The likely high-value combination is the current Core pipeline, array theory, quantifier-free frames, shared SMT environments, and native `old`.

### 10. Diagnostics and source locations

Upstream added:

- Per-invariant source ranges (`3fe8f89e`)
- File-relative diagnostics
- Assertion metadata carried directly on failures
- Better procedure-boundary error isolation
- Structured `Pipeline.Message` diagnostics
- User-facing summaries rather than internal labels

#### Opportunity

Improve StrataSolidity output and SARIF with:

- Exact highlighting of failing NatSpec expressions
- Separate locations for multiple loop invariants
- Cleaner diagnostic categories
- Related locations for call sites and assertion sites
- Stable summaries instead of generated labels
- Better imported-file diagnostics

This is one of the lowest-risk, highest-visible-value improvements after compatibility is restored.

## Confirmed migration challenges

An isolated build against upstream `79c2cd6c` confirmed the first concrete blockers:

- Missing `Strata.DDM.*` modules after the Strata-DDM extraction
- Missing `Strata.Languages.Laurel.Laurel`
- Missing `Strata.Languages.Laurel.LaurelToCoreTranslator`
- Cascading import failures across the Solidity dialect, translator, tests, and CLI

Further expected work includes:

- Making `AstNode.source` and `Identifier.source` non-optional
- Adapting identifier comparison to rely on `uniqueId`
- Adapting primitive operations represented as static calls
- Adapting changed value-return lowering
- Handling removed Laurel function constructs
- Adopting new diagnostics and translation result types
- Updating the `Core.verify` invocation
- Regenerating golden outputs affected by labels, obligations, or diagnostics

The isolated upstream checkout and its Strata-DDM dependency resolved and built. The blocker is StrataSolidity API adaptation, not Lean or a broken upstream revision.

## Upstream changes since the first analysis (79c2cd6c → d1fc3a0)

90 further commits. The ones that matter for StrataSolidity:

**Packaging / breaking**

- `c9975ac6` Lean 4.31 support; the toolchain moved v4.29.1 → v4.31.0.
- `c5f14dff`, `a2c484c3` Laurel moved under a single `StrataLaurel` module root.
- `6b5b132b` Strata Core decoupled from the Laurel layer.
- `0dd1b9c7` (breaking) source names may not start with `$` (`validateNoDollarNames`). StrataSolidity emits none today; generated names must stay `$`-free.
- `02f873ed` (breaking) every type argument must be inferable at resolution or it is reported. Relevant to `mapConst(...)`, whose key type comes from the expected type.
- `10914f1f` internal function declarations lowered to lambda values.

**Laurel language**

- `f003edd8` integer bitwise AND / OR / XOR and a bitvector layer. StrataSolidity models `&`, `|`, `^`, `<<`, `>>`, `~` as uninterpreted `bit_*` helpers today — a candidate for real semantics.
- `968a8da8` partial `Map<K, V>`; `062a03cc` opaque `Sequence`; `1005e24d` string ordering.
- `4e7b392d` dynamic method dispatch with Liskov (behavioral-subtyping) checking, plus fixes `905c5e29`, `8461d4ee`, `273f4d4d`. Relevant to inheritance / `virtual`/`override`.
- `5356bee7` invoking a lemma (assume its postcondition).
- `8c00f23f` the heap is modelled as a file-scope global, reusing globals threading.
- `773b4832`, `84fb7001`, `b2d0fe9a` a Laurel interpreter, run on every executable upstream test (concrete execution of generated Laurel is now possible).
- `d32a80c2` checked Laurel builder (`derive_laurel_ops`).
- `8b377573` catch bindings typed from any thrown type; handlers are never dropped silently.

**Core / verification**

- `764b0316` nat/pos counterexamples via UF + axioms re-query. **Also makes `Core.verify` merge VC results by (summary, source range)** — see the port notes below.
- `ff8241b8`, `a2325c03`, `56e10b54` callers choose the verification pipeline's phases; every phase is named; new `hasObligationForm` fact.
- `bcca08fb` correct procedure call semantics; `3605af89` block declarations no longer leak into the following scope.
- `23927ce9` bounded quantifiers whose instance count is known are unrolled.
- `ce198541`, `cd3c7eba`, `20f1903c` concrete Hoare triples and event-trace Hoare logic (metatheory; no frontend impact yet).

**Soundness fixes worth knowing about**

- `90f211c4` preconditions of calls inside contracts are checked.
- `3942ef41` postcondition well-formedness assumptions are chained.
- `090c7cb0` nondeterministic commands can no longer produce ill-typed values.
- `d9fb58b1` a variable read before a lifted write is snapshotted.
- `7a19c615` a value type in a `modifies` clause is rejected.

**SMT**

- `93ebadf4`, `078a10bc` names are escaped per target alphabet before being emitted as SMT-LIB symbols.
- `9e54827b` quantifier triggers are `List (List Term)`; `400e553c` SMT query typing/denotation.

## Compatibility port outcome

Commits on `strata-update`, each building on its own:

1. `chore(deps)`: re-pin, toolchain, manifest, and the compile-level API port (imports, `StrataDDM` namespace, `PrimitiveOp` → `StaticCall "$op"`, non-optional `source`, `Parameter?`, `While` `postTest`, `isFunctional` removal, `ModifiesGroup`, `Core.verify` signature).
2. `fix`: `const` → `mapConst` (Laurel resolution no longer sees Core builtins).
3. `fix`: uninterpreted helpers (`keccak256`, `abi_encode*`, `bit_*`, …) become transparent procedures with a deterministic `Hole` body. A bodiless procedure is now havocked per call, which broke `keccak256(d) == keccak256(d)`.
4. `fix`: every postcondition gets a distinct summary (`ensures <clause>`, `modifies frame (<var>)`, `invariant #n`). Otherwise the new VC merging collapses all postconditions of a function into one result.
5. `fix`: passing VCs located in the Laurel prelude (four `$div`/`$mod` wrapper checks) are not reported; failing ones still are.

Semantic subtleties to keep in mind:

- `Body.Opaque … []` now means *unframed*; "changes nothing" is `[{ targets := [] }]`. The port always emits one group.
- Obligation labels changed from `postcondition_N` / `callElimAssert_requires_N` to `assert(<n>)`; the useful text is now the property *summary*, not the label.
- `Strata.Laurel.translate` still returns `(Option Core.Program × List Message)`; StrataSolidity still calls `Core.verify` directly with `VerifyOptions.default` (array theory off), whereas Laurel's own `verifyTo*` APIs default to array theory on and `removeIrrelevantAxioms := .Precise`.

Pre-existing gaps found while establishing the baseline (present at `349b1cf4` too):

- An `@custom:strata invariant` in contract-level NatSpec is silently ignored (only state-variable NatSpec is read). `test_spec_failures.sol` expects `breakInvariant` to fail, but no obligation is generated.
- An `@custom:strata loop-invariant` written as a comment inside a function body is silently ignored (solc does not attach NatSpec to statements).
- SARIF classifies every result by `VCOutcome.passAndReachable`, which requires a reachability check that is not run by default, so every passing obligation is reported as `strata/unknown`/`open`; rule ids are derived from labels that no longer contain `ensures`/`invariant`.
- Solver/encoding errors (`VCResult.outcome = .error`) are counted as "unknown" in text mode and do not affect the exit code.

## Phased implementation plan

### Phase 0: Establish the migration baseline

1. Create a dedicated upstream-port branch.
2. Record the old and target Strata SHAs.
3. Run and preserve current build, unit, golden, SARIF, and benchmark results.
4. Pin the target Strata SHA explicitly; do not depend on a floating submodule branch.
5. Keep the first port behavior-preserving.

### Phase 1: Restore compilation

1. Update imports for Strata-DDM and Laurel module moves.
2. Remove obsolete Ion input support rather than porting unused compatibility code.
3. Update `lake-manifest.json` through `lake update`.
4. Adapt source metadata and identifier constructors in `SolTranslator/Types.lean` so most call sites remain unchanged.
5. Adapt Laurel translation result handling.
6. Adapt the Core verifier invocation and pipeline context.
7. Run `lake build` after each migration layer.

### Phase 2: Restore behavioral compatibility

1. Run Lean unit and characterization tests.
2. Run the complete Solidity fixture corpus.
3. Run golden and exit-code tests.
4. Run SARIF schema validation.
5. Classify every output change as formatting, obligation decomposition, solver behavior, or semantic behavior.
6. Do not accept semantic changes merely by regenerating golden files.

### Phase 3: Adopt upstream diagnostics

1. Use structured pipeline messages.
2. Preserve exact NatSpec and invariant source ranges.
3. Improve SARIF rule IDs, messages, and related locations.
4. Add tests for multiple invariants on one loop and imported Solidity files.

### Phase 4: Adopt native `old` and inout semantics

1. Start with scalar state variables.
2. Remove synthetic scalar `<name>_in` parameters.
3. Migrate mapping state.
4. Migrate internal-call state threading.
5. Define procedure-entry versus loop-entry `old` semantics explicitly.
6. Verify all old-state tests and add nested-call regressions.

### Phase 5: Evaluate array-theory frame optimization

1. Confirm generated mapping frames reach the upstream optimized path.
2. Compare default and array-theory SMT output.
3. Benchmark ERC20, vault, escrow, and nested mappings.
4. Measure quantifier count and unknown-result rate.
5. Consider making array theory the default only if correctness and performance are consistently better.

### Phase 6: Investigate struct fields through mappings

1. Add a minimal mapping-to-struct fixture.
2. Inspect each Laurel pipeline stage.
3. Identify the exact remaining blocker.
4. Implement a frontend fix if current upstream provides sufficient heap support; otherwise document a precise upstream requirement.

### Phase 7: Emit native Laurel constructs

Adopt these independently, with tests and benchmarks for each:

1. Do-while loops
2. Increment, decrement, and compound assignment
3. Exceptions and try/catch
4. Instance procedures
5. Inheritance and override resolution
6. Native sets where they replace ad hoc map encodings

### Phase 8: Performance and release assessment

1. Rerun the full benchmark baseline.
2. Compare generated Laurel, Core, and SMT artifacts.
3. Record performance and outcome changes in the changelog.
4. Update README, mdBook, limitations, and the authoritative requirements.
5. Pin the adopted Strata and Strata-DDM revisions for reproducible builds.

## Success criteria

The compatibility port is complete when:

- `lake build` and `lake test` pass.
- The golden suite and exit-code contract pass.
- SARIF validates against the vendored 2.1.0 schema.
- Existing supported contracts retain their expected verification outcomes.
- Any changed obligations or diagnostics are reviewed rather than blindly accepted.
- The target Strata SHA is pinned and documented.

An upstream improvement is complete only when it has:

- A focused design decision
- Positive and negative regression tests
- Benchmark evidence where performance is relevant
- Updated user-facing documentation and limitations
- No weakening of soundness or unsupported behavior hidden as a successful result
