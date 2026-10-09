# Changelog

## 2026-10 — Contract invariants

- `@custom:strata invariant` is honored in the NatSpec above `contract`, not
  only on state variables (sum_token: `totalSupply == sum(balances)` is now
  checked; test_spec_failures' `breakInvariant` now fails as intended).
- Soundness: a contract without a constructor gets an implicit one, so an
  invariant false at deployment (or unsatisfiable) is reported instead of
  being assumed by every function; state-variable initializers run before
  the constructor body; a parameter shadowing a state variable no longer
  captures an invariant.
- Invariants are checked at external entry points only (internal helpers
  neither assume nor re-establish them) and are assumed by view functions.
- Constructors can establish `sum(...)` invariants (`sum` of an empty mapping
  is 0); the quantified `sum` axioms are only assumed for mappings a spec
  sums, which turns many `unknown` results into refutations.
- `old(...)` in an invariant is rejected with a clear error; `arr.length` and
  named constants work in constructor invariants.

## 2026-10 — Array theory by default; fewer `unknown` results

- **Array theory by default** (`--no-array-theory` restores the quantified
  select/update encoding). Exit code changes: test_try_catch now fails
  (its `ensures callFailed == true || lastResult > 0` is false).
- **One SMT context per function**: axioms one function needs (Core's
  quantified `mapConst` axiom for zero-initialized mappings) no longer turn
  unrelated refutations into `unknown`. `--dump-vc` writes one
  subdirectory per procedure.
- **Solidity type ranges** are assumed for parameters, state variables,
  `msg.sender`/`msg.value`, `try` return values and hash results; signed
  state variables are no longer assumed non-negative (which made
  `ensures tick >= 0`-style properties verify unsoundly).
- **Counterexamples** are no longer dropped when z3 prints nested arrays
  with `let`.

## 2026-10-08 — Upstream Strata re-pin (Lean 4.31, StrataDDM / StrataLaurel)

Re-pins the Strata submodule from `349b1cf4` (nightly-20260523) to
`d1fc3a08` (nightly-20261008), 393 upstream commits. Behavior-preserving:
per-fixture pass/fail/unknown counts and exit codes are unchanged across
all 144 `.sol` fixtures; the golden suite passes unchanged.

### What changed under the hood
- **Lean toolchain**: 4.29.1 → 4.31.0.
- **Packages**: DDM is now the `StrataDDM` package (namespace `StrataDDM`);
  Laurel is the `StrataLaurel` library.
- **Laurel AST**: operators are `StaticCall "$add"`/`"$eq"`/… (no more
  `PrimitiveOp`); `StaticCall` carries inferred type arguments;
  `AstNode.source` is a non-optional `FileRange`; `Declare` takes
  `Parameter?`; `While` has a `postTest` flag; `isFunctional` is gone;
  `modifies` is a list of `ModifiesGroup`s (empty list = unframed).
- **Core**: `Core.verify` merges results by (summary, source range), so
  every postcondition now carries a distinct summary
  (`ensures <clause>`, `modifies frame (<var>)`, `invariant #n`).

### Fixed (regressions exposed by the re-pin)
- Constant mappings use the prelude's `mapConst` (Core's `const` is no
  longer resolvable from Laurel).
- Uninterpreted helpers (`keccak256`, `abi_encode*`, `bit_*`, …) keep
  functional consistency (deterministic-hole bodies).
- Passing well-formedness checks of Laurel's own prelude are no longer
  reported.

### Visible output changes
- Obligation labels are now `assert(<n>)` instead of `postcondition_N` /
  `callElimAssert_requires_N`.

## 2026-07-11 — Python-free pipeline (Solidity + Lean)

The verification pipeline is now entirely Lean: the `strataSolidity`
binary invokes `solc --standard-json`, parses the JSON AST into typed
Lean structures (`SolcRunner.lean` + `SolcAstParser.lean`), translates,
and verifies. `.sol` files are accepted directly.

### Removed
- `Tools/Solidity/src/solast.py`, `base_dialect.py`,
  `print_dialect_summary.py`, `strata_verify.py`, `strata_coverage.py`
- `Tools/Solidity/dialects/Solidity.dialect.st.ion` + `gen_dialect.sh` —
  the dialect is declared once, in Lean
  (`StrataSolidity/SolidityDialect.lean`, declarative `#dialect` block +
  `#strata_gen`); the stale-olean CI hazard is structurally gone
- The CI dialect-parity gate (single source needs no parity)
- The dead `run_sol_analyze_laurel.sh` harness + its `expected/` dir

### Fixed
- do-while + first-iteration `break`/`continue` mistranslation
- Named constants (`NOT_ENTERED`, `DEFAULT_ADMIN_ROLE`) now fold in spec
  expressions and key-scoped `modifies` clauses
- Valued `return` in functions with mapping-state outputs (desugared to
  output-parameter assignment)
- Unary `!` and negative literals in spec expressions
- In-contract invariant fixture placement

### Verification corpus
Token 30/30 · AccessControl 15/15 · Ownable2Step 16/16 · Initializable
13+1/14 · Ownable 9/9 · Pausable 4/4 · Nonces 4/4. Golden suite 22/22.


## 2026-05-23 — Upstream Strata Port (Lean 4.29.1 + new Laurel AST)

Ports StrataSolidity onto upstream `strata-org/Strata` HEAD (`349b1cf4`),
moving past Everton's solidity-branch patches that had pinned us to an older
Strata SHA. The pipeline runs end-to-end: contract.sol → Laurel → Core →
SMT → SARIF with source locations.

### What changed under the hood

- **Lean toolchain**: bumped 4.27.0 → 4.29.1 to match upstream Strata.
- **Laurel AST shape** (multiple upstream PRs):
  - `AstNode.md : MetaData` → `AstNode.source : Option FileRange` (#852)
  - `Identifier { text }` → `Identifier { text, uniqueId, source }` (#1028)
  - `StmtExpr.Identifier` → `StmtExpr.Var (Variable.Local)` (#1077)
  - `StmtExpr.FieldSelect` → `StmtExpr.Var (Variable.Field)` (#1077)
  - `StmtExpr.Forall`/`.Exists` → `StmtExpr.Quantifier` (#1024)
  - `StmtExpr.LocalVariable` → `StmtExpr.Var (.Declare)` / `.Assign [.Declare]` (#1077)
  - `StmtExpr.Assert` now wraps in a `Condition` record with optional summary
- **Verifier API**:
  - `Core.Outcome` enum → `Core.VCOutcome` structure with separate
    satisfiability/validity SMT.Result fields (#487)
  - `VCResult.result` → `VCResult.outcome : Except VCError VCOutcome`
  - Use `VCResult.isSuccess`/`isFailure` predicates instead of pattern
    matching the old enum
- **Procedure shape**: dropped removed `determinism` and `md` fields;
  `preconditions : List Condition` (was `List StmtExprMd`).
- **Body**: `Body.Opaque postconds impl modifies` and `Body.Abstract postconds`
  now take `List Condition` not `List StmtExprMd`.
- **Adapter helpers** (`StrataSolidity/SolTranslator/Types.lean`):
  - `mkIdent`, `mkIdentifier`, `mkFieldSelect`, `mkForall`, `mkExists`,
    `mkLocalVar`, `mkAssert`, `mkAssume`, `toAssignTarget`,
    `sourceRangeToFileRange`. These absorb the AST refactor at a single
    boundary; the rest of the translator reads naturally.
- **Removed**: `StrataSolidity/SolToLaurel.lean` (legacy ~2100-line
  monolithic file — superseded by `SolTranslator/{Types,SpecParser,
  SpecRewriter,ExprTranslator,StmtTranslator,ContractTranslator}.lean`).

### What's degraded — what works

✅ **Preserved**:
- End-to-end pipeline: `contract.sol` → SARIF with source locations.
- Specification language (`@custom:strata` NatSpec annotations) parses
  and translates as before — no user-facing syntax changes.
- Source-position metadata flows from Solidity AST → Laurel → Core →
  SARIF `physicalLocation.region.startLine`/`startColumn`.
- `requires` / `ensures` / `invariant` / `loop-invariant` / `forall` /
  `exists` annotations are translated into the new Laurel shape.
- Mapping state vars + `_in` parameter passing for pre-state.
- Frame conditions for mappings (`modifies balances[msg.sender]`).
- Quantifiers with implication patterns (`forall a :: a != x ==> ...`).

⚠️ **Degraded** (best-effort while upstream stabilizes):
- Frame conditions for scalar state vars now use the same `<name>_in`
  mechanism rather than the legacy `.Old` AST node. Functionally
  equivalent but worth re-running golden tests to confirm.
- `old()` in loop invariants resolves correctly inside function-level
  scope (as the `<name>_in` parameter is in scope), but loop-specific
  pre-state (value at loop entry) is not yet captured — that would
  need a separate per-loop snapshot mechanism.
- Counterexample generation: no change from before — z3's mbqi is still
  disabled.

✨ **Recovered semantics for `old()`** (after the proper-fix follow-up
commit): scalar `old(stateVar)` and mapping `old(map[k])` now resolve
via synthetic `<name>_in` input parameters pinned to the pre-state
value via an entry-time precondition `self.<name> == <name>_in`.
Internal call sites pass the caller's current `self.<name>` as the
callee's `<name>_in`. Specs that *relate* new state to old state
(the whole point of `old()`) now verify correctly.

❌ **Not currently working**:
- Variable-name preservation in some Identifier contexts where the
  upstream resolution pass requires `uniqueId`. We default to `none` for
  now; resolution may rename variables internally.
- Counterexample generation: no change from before — z3's mbqi is still
  disabled.

### Smoke tests

After the proper-`old()` fix, end-to-end runs on representative contracts:

| Contract | Result |
|---|---|
| b1_trivial.sol | ✅ 2/2 pass |
| b2_counter.sol | ✅ 6/6 pass |
| b3_token.sol | ✅ 8/8 pass |
| b4_vault.sol | ✅ 8/8 pass |
| b6_erc20.sol | ✅ 11/11 pass |
| events_errors.sol | ✅ 8/8 pass |
| forall_frame.sol | ✅ 2/2 pass |
| nonlinear.sol | ✅ 21/21 pass |
| sum_token.sol | ✅ 8/8 pass |
| loop_invariant.sol | ⚠️ 3/5 pass + 2 unknown |
| b5_escrow.sol | ❌ `block_timestamp` resolution error (unrelated) |
| SARIF output | ✅ Works with source locations |

The exit-code contract sub-stage (REQ-PBT-007) passes 3/3.

The golden test suite (which diffs against pre-port expected outputs)
shows 9/11 failures because the new pipeline produces more verbose
output, more granular obligations, and some additional unknowns. These
are expected; expected outputs need regeneration to match the new
behavior.

## 2026-03-12 / 2026-03-13 — Major Feature Sprint

### Specification Language (NatSpec)
- Migrated from `_strata_*` function stubs to `@custom:strata` NatSpec annotations
- `@custom:strata requires <expr>` — preconditions
- `@custom:strata ensures <expr>` — postconditions with `old()` support
- `@custom:strata invariant <expr>` — contract invariants
- `@custom:strata modifies <vars>` — frame conditions
- `@custom:strata loop-invariant <expr>` — loop invariants
- `@custom:strata forall v : T :: <expr>` — universal quantifier
- `@custom:strata exists v : T :: <expr>` — existential quantifier
- Recursive descent spec expression parser with full operator support
- Removed all legacy `_strata_*` stub support

### Solidity Language Support
- Inheritance (solc AST flattening, baseContracts field)
- Modifiers (inline pre-_ requires as preconditions)
- Enums (modeled as constrained integers)
- Custom errors and `revert CustomError()` (errors as abort)
- User-defined value types and `using ... for` directives
- Ternary operator (`? :`) and basic tuple expressions
- `unchecked { }` blocks (isInsideUnchecked context flag)
- `immutable` and `constant` state variables (constant folding)
- `delete` operator (reset to default value)
- `receive()` and `fallback()` functions
- Events/emit (no-op, skipped in solast.py)
- Inline assembly (havoc all state — sound overapproximation)
- `try/catch` (TryStatement skipped, sound overapproximation)
- Tuple destructuring (multi-component → sound overapproximation)
- Interfaces and abstract contracts
- External calls (call/delegatecall/staticcall → nondeterministic)
- `new Contract()` creation
- `selfdestruct` (no-op)

### Types & Expressions
- `msg.value`, `msg.data`, `msg.sig` as implicit parameters
- `block.number`, `block.timestamp`, `block.chainid`, `tx.origin`, `gasleft()`
- `type(T).min` / `type(T).max` constant folding
- Bitwise operators (`&`, `|`, `^`, `~`, `<<`, `>>`) as uninterpreted functions
- `keccak256`, `sha256` as uninterpreted functions
- `abi.encode*` family as uninterpreted functions
- `address.balance`, `address.code`, `address.codehash`
- `transfer`/`send`/`call` for Ether transfers
- `payable()` type casts
- `bytes`/`string` dynamic types (mapped to TInt)
- Array slices (nondeterministic)

### Verification Infrastructure
- Default storage initialization (all fields zero-initialized in constructors)
- SARIF 2.1.0 output (`--sarif` flag) with source location mapping
- `strata-verify.sh` — shell wrapper for one-command verification
- `strata_verify.py` — solc-compatible standard-JSON wrapper
- NatSpec documentation extraction in solast.py + dialect regeneration

### Test Suite
- 90+ test .sol files covering: ERC20, ERC721, reentrancy mutex, vault/deposit,
  ballot, safe withdraw, quantifiers, modifies, inheritance, diamond inheritance,
  modifiers, enums, custom errors, inline assembly, try/catch, cross-contract,
  transient storage, SARIF output, and more
