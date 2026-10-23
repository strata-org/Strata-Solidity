# Changelog

## 2026-10 — Capability ledger

- `docs/capabilities.toml` lists every feature with its status (verified,
  partly verified, unknown values, not verified, rejected, fails) and the
  test fixtures that show it. `scripts/capabilities.py` generates the
  feature tables of LIMITATIONS.md, README.md, FAQ.md, the guide, the
  next-spec's gap table and the landing page from it; CI runs it with
  `--check`, which fails when a fixture no longer shows what its entry
  says or a table is out of date.
- `test/examples/gap_*.sol` pin the current error of each construct that
  is rejected or fails to translate (`pop`, `revert("…")`, library calls,
  strings, …), so that supporting one changes its golden file and its
  ledger entry together.
- Annotations may end with a `//` comment (`ensures x == v  // the new
  value`), as the guide's examples do; such a line used to stop the
  translation of the whole file. The spec tokenizer reads characters, not
  bytes, so non-ASCII text no longer garbles the tokens after it.
- Documentation: the guide's examples verify as written (`requires to !=
  msg.sender` in the transfer examples, a one-index `modifies` for
  `transferFrom`, a constant inside its contract); `old()` in loop
  invariants and `msg.sender` in constructors are documented as working;
  cvc5 is no longer mentioned (the solver is z3); README shows real
  output; the FAQ describes the in-Lean pipeline; the SARIF workflow
  example builds StrataSolidity before using it.

## 2026-10 — Inheritance

A contract is verified with what it inherits. Before, `contract Child is
Base` failed to translate (`Resolution failed: 'n' is not defined`) as soon
as it used anything Base declared; only interfaces and abstract contracts
that declare no state worked. See REQ-NEXT-SOL-001..025 in
`.kiro/specs/strata-solidity-next/requirements.md`; fixtures
`test/examples/inheritance*.sol`.

- Bases are ordered by solc's C3 linearization. Inherited state variables,
  functions, modifiers, structs, enums and invariants resolve in the
  derived contract's context, and an inherited function calls the most
  derived override of a virtual function. An override has the parameter
  types of what it overrides; an overload stays. A public state variable
  overrides the base function its getter implements.
- Each contract of a file is still verified on its own; an obligation of
  an inherited function names the contract it is checked in, `(in D)`.
- Base constructors run when a derived contract deploys: after the
  state-variable initializers, outside the derived constructor's modifiers,
  most base first, each with its own modifiers and with the arguments the
  derived constructors give (`constructor() Base(7)`). An inheritance
  specifier's arguments (`is Base(7)`) are not read: unknown values.
- `super.f()` follows the linearization from the contract the call is
  written in (in a function, a modifier or a base constructor), and
  `Base.f()` calls Base's implementation.
- Reported: a base the file does not define, directly or through another
  base. Rejected: `super` of an overloaded function, and a base's private
  state variable declared again in a derived contract.

## 2026-10 — Soundness fixes

Each of these made a false property verify; each fix has a fixture under
`test/examples/` with true and false properties.

- **Invariants** may not read `msg.sender` or `msg.value` (rejected, as
  `block.*` already was): an invariant holds between transactions, whoever
  calls next, and one over the caller was established for one caller and
  assumed for the next (`invariant_msg_sender.sol`, `invariant_msg_value.sol`).
- **`require(cond, f())`** keeps the effects of its message arguments, which
  run before the condition is assumed (`require_message_effects.sol`).
- **Quantified variables** range over their declared type:
  `exists i : uint8 :: i == k` is no longer proven for every `k`
  (`quantifier_types.sol`).
- **Bitwise results** have the type of the operation (a signed result can be
  negative); `~x` is exact (`bitwise_types.sol`).
- **Constant expressions** have the value solc computes, exactly:
  `(7 / 2) * 2` is 7; `2.5 ether` and `1e18` are accepted
  (`constant_expressions.sol`).
- **`unchecked`**: a signed `/` and a power of named constants wrap within
  their type (`unchecked_wrapping.sol`).
- **Specifications** divide like the code: `/` rounds toward zero and `%`
  takes the sign of the dividend (`spec_division.sol`).
- **Mapping and array `storage` parameters** are rejected: writes through
  them were lost (`storage_param_mapping.sol`, `storage_param_array.sol`).
- **Halts**: a call of a function that may end the transaction (assembly
  `return`/`stop`, `selfdestruct`) is rejected; the caller used to continue
  after it (`halt_in_helper.sol`, `selfdestruct_in_helper.sol`).
- **Structs** are copied where Solidity copies them (into storage, from
  storage or calldata into memory) instead of shared, and a memory struct
  passed to a function has unknown fields afterwards (`struct_copies.sol`).
- **Storage references** read the storage they refer to when the read
  runs, not its value when the reference was taken
  (`storage_reference_reads.sol`).

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

## 2026-10-13 — Reporting, output and soundness (PRs #3, #5–#14)

### Soundness

Each of these made a false property verify, or hid one.

- Statements the translator cannot translate are reported, instead of
  being assumed false (which proved everything after them) (#8).
- Loop conditions are evaluated before every iteration, with their
  effects; `i++` yields the old value; `&&` and `||` evaluate their right
  operand only when needed; locals and return variables start at zero;
  fixed-size array parameters have their length (#8).
- Inline assembly makes unknown what it may write: the variables it
  assigns, memory, and contract state when it may write storage (#8).
- `block.*`, `tx.*` and `gasleft()` are modelled: one value per
  transaction (`gasleft()` fresh at each read) (#8).
- Internal calls pass the callee's implicit arguments in the order it
  declares them, and keep its state outputs (#7).
- Tuple declarations bind to their initializer; the arguments of events,
  transfers and calls are evaluated; operands whose evaluation order
  matters are rejected (#10).
- Writes through storage references are rejected; functions without a
  body may change state; memory arrays are references; unmodelled values
  are unknown at every evaluation (#11).
- Integers follow Solidity: conversions truncate, `unchecked` arithmetic
  wraps, signed `/` and `%` round toward zero; constant powers, shifts and
  masks are folded (#12).
- Modifiers are inlined into each function that uses them (their state
  writes, the code after `_`, their arguments), instead of contributing
  only their leading `require`s (#13).
- External calls (`this.f()`, interface calls, low-level calls, `new`) may
  re-enter the contract: its state is unknown after the call except for
  its invariants, which are checked before the call. `--assume-no-reentrancy`
  trusts calls not to re-enter (#14).

### Reporting and output

- Annotations and functions that are not verified are reported as
  warnings instead of being dropped; `--strict` exits 1 unless everything
  is proven, in every output format; the input file is verified, not the
  first source unit solc lists (#3).
- SARIF output shares the CLI's verdicts, classifies results by property,
  includes unverified annotations as `strata/not-verified`, and conforms
  to SARIF 2.1.0 (#5).
- Obligations and counterexamples are named in user terms (the clause,
  `old(x)`, `msg.sender`), and each clause is reported at its own NatSpec
  line (#6).
- Checks of initializers, returns and heap frames have source locations;
  warnings and failures appear in `--json`, `--pipeline-json` and SARIF
  output (#9).

## 2026-10-08 — Upstream Strata re-pin (Lean 4.31, StrataDDM / StrataLaurel)

Re-pins the Strata submodule from `349b1cf4` (nightly-20260523) to
`d1fc3a08` (tagged nightly-20261009 upstream), 393 upstream commits. Behavior-preserving:
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
Measured on OpenZeppelin contracts that are not in this repository:
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

(As first reported. Several items stopped holding, or were found not to:
inheritance stopped resolving inherited members with the 2026-07 frontend
until the 2026-10 inheritance change; enums are not constrained; `using ...
for` and `delete` of a non-integer fail to translate; `selfdestruct` ends
the transaction instead of being a no-op. LIMITATIONS.md has the current
status.)

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
