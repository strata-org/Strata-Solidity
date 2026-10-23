# Requirements Document — `strata-solidity-next`

## Introduction

This document holds the requirements that change behavior relative to the
**retrospective baseline** in
[`../strata-solidity-baseline/requirements.md`](../strata-solidity-baseline/requirements.md).
The baseline describes what the code did when it was written and introduces
no new behavior; this document is the only place where its `GAP-*` items
are closed.

Every requirement below cites the baseline IDs it modifies or closes, as
`CONTRIBUTING.md` requires. Baseline requirements not cited here are
unchanged.

---

### Requirement 1 — Inheritance: a contract is verified with its inherited members

**Closes:** `GAP-009` (multi-contract inheritance with virtual dispatch),
except for the cases REQ-NEXT-SOL-022..025 report or reject.
**Modifies:** `REQ-SOL-004` (single inheritance via `is`),
`REQ-SOL-005` (diamond inheritance via `baseContracts`),
`REQ-SOL-006` (virtual dispatch across contracts).

**User Story:** As a developer verifying a contract that inherits from
another, I want what it inherits to be part of what is verified, so that a
contract built from base contracts can be specified and proven at all.

**Context.** The baseline's `REQ-SOL-004` and `REQ-SOL-005` say inheritance
is accepted "flattened at the AST level", and `design.md` §12.9 attributes
that flattening to `solast.py`. Neither held once the in-Lean frontend
replaced the Python one: solc's AST lists only the members written in a
contract, with its bases named in `baseContracts`, and
`ContractTranslator.translateContract` read only a contract's own members,
so any use of an inherited member failed to translate. These requirements
replace that behavior.

#### Acceptance Criteria — Flattening

1. REQ-NEXT-SOL-001. THE Solidity_Translator SHALL verify a contract as the
   flattening of its transitive bases and itself, so that every inherited
   member resolves in the derived contract's own context (its `self`
   parameter, its state parameters, its invariants).
2. REQ-NEXT-SOL-002. THE Solidity_Translator SHALL order a contract's bases
   by solc's C3 linearization (`linearizedBaseContracts`): for
   `contract C is B1, …, Bn`, `L(C) = C :: merge(L(Bn), …, L(B1), [Bn, …, B1])`.
   Inherited members are taken most base first, the reverse of `L(C)`.
3. REQ-NEXT-SOL-003. WHERE a more derived contract declares a function with
   the name and parameter types (data locations aside) of an inherited one,
   or a `receive`, `fallback` or modifier of the same name, THE
   Solidity_Translator SHALL verify the more derived declaration and not
   the inherited one. A function of the same name with other parameter
   types is an overload, and both are verified.
4. REQ-NEXT-SOL-004. WHERE a public state variable shares its name with an
   inherited function (which its getter overrides), THE Solidity_Translator
   SHALL NOT verify that function in the deriving contract.
5. REQ-NEXT-SOL-005. THE Solidity_Translator SHALL merge inherited state
   variables together with their initializers, `constant` values,
   `immutable` markers and Solidity type names, and inherited structs,
   enums and modifier definitions.
6. REQ-NEXT-SOL-006. THE Solidity_Translator SHALL emit a struct's type
   definition and its synthetic constructor procedure once, for the
   contract that declares the struct.
7. REQ-NEXT-SOL-007. THE Solidity_Translator SHALL continue to verify every
   contract of the file on its own, so that a base's specifications are
   checked against the base as well as against each contract that inherits
   them; an obligation of an inherited function SHALL name the contract it
   is checked in (`ensures … (in D)`).
8. REQ-NEXT-SOL-008. WHERE an inherited function calls a virtual function,
   THE Solidity_Translator SHALL call the most derived override of it.

#### Acceptance Criteria — Invariants

9. REQ-NEXT-SOL-009. THE Solidity_Translator SHALL check a base contract's
   `@custom:strata invariant`, whether written in the base's NatSpec or on
   one of its state variables, at the external entry points of every
   contract that inherits it, under the rules of `REQ-SPEC-*` for the
   deriving contract.
10. REQ-NEXT-SOL-010. WHERE a base is an `interface` or a `library`, which
    have no state, THE Solidity_Translator SHALL NOT take invariants from
    it.

#### Acceptance Criteria — Constructors

11. REQ-NEXT-SOL-011. THE Solidity_Translator SHALL run each base
    constructor when a deriving contract's constructor (explicit, or the
    implicit one that checks the initial state) runs: after every
    state-variable initializer, before the deriving constructor and outside
    its modifiers, most base first (solc's legacy code generator order).
12. REQ-NEXT-SOL-012. THE Solidity_Translator SHALL run a base constructor
    with its own modifiers, in a block that a `return` in it exits, with its
    parameters and locals renamed apart from the deriving constructor's.
13. REQ-NEXT-SOL-013. THE Solidity_Translator SHALL bind a base
    constructor's parameters to the arguments that the most derived
    constructor naming its contract gives (`constructor() Base(7)`),
    evaluated most derived first in the scope of that constructor.
14. REQ-NEXT-SOL-014. IF a base constructor's arguments are given in an
    inheritance specifier (`is Base(7)`), which the AST the translator reads
    does not carry, or not at all (an abstract contract), THEN THE
    Solidity_Translator SHALL give its parameters unknown values of their
    types.
15. REQ-NEXT-SOL-015. IF a base constructor a constructor runs uses a
    struct-valued mapping, THEN THE Solidity_Translator SHALL NOT verify
    that constructor, nor the invariants it would establish, and SHALL emit
    a warning.

#### Acceptance Criteria — `super` and explicit base calls

16. REQ-NEXT-SOL-016. THE Solidity_Translator SHALL resolve `super.f(...)`
    to the implementation of `f` that follows, in the linearization of the
    contract being verified, the contract in which the call is written: the
    contract that defines the function, modifier or base constructor it is
    in.
17. REQ-NEXT-SOL-017. THE Solidity_Translator SHALL resolve `Base.f(...)`,
    for a base `Base`, to the first implementation of `f` in `L(Base)`.
18. REQ-NEXT-SOL-018. THE Solidity_Translator SHALL emit each overridden
    implementation that such a call reaches, directly or through another
    one, as an internal procedure of the deriving contract named
    `__base_<DeclaringContract>_<function>`, and no other.
19. REQ-NEXT-SOL-019. THE Solidity_Translator SHALL bind the named
    arguments of such a call by name.
20. REQ-NEXT-SOL-020. IF such a call names an overloaded function, or has
    no implementation to call, or reaches an implementation that uses a
    struct-valued mapping, THEN THE Solidity_Translator SHALL fail with an
    `unsupported` error.

#### Acceptance Criteria — Reporting and rejection

21. REQ-NEXT-SOL-021. THE Solidity_Translator SHALL emit the warnings of
    `REQ-OUT-*` and `REQ-SPEC-*` for a contract's own declarations only, so
    that an inherited declaration is reported once, against the contract
    that declares it.
22. REQ-NEXT-SOL-022. IF a contract's linearization includes a contract
    that the verified file does not define (an imported base, directly or
    through another base), THEN THE Solidity_Translator SHALL emit a warning
    naming it and the deriving contract, and SHALL verify the contract
    without its members. This is the remaining part of `GAP-009`.
23. REQ-NEXT-SOL-023. IF a contract and one of its bases declare state
    variables of the same name (a base's private one), THEN THE
    Solidity_Translator SHALL fail with an `unsupported` error: they are
    different variables.
24. REQ-NEXT-SOL-024. Note. Overloads whose parameters are all integers or
    addresses have the same parameter types in Laurel and are rejected, in
    a single contract too (unchanged from the baseline).
25. REQ-NEXT-SOL-025. Note. Base constructors run in solc's legacy order;
    the IR code generator (`--via-ir`) initializes each contract's state
    variables just before its constructor runs.

#### Characterization

26. REQ-NEXT-TEST-001. THE Golden_Harness SHALL cover, each with true and
    false properties: inherited state, internal calls, modifiers,
    invariants, virtual dispatch and a getter override
    (`test/examples/inheritance.sol`); overloads
    (`inheritance_overloads.sol`); base constructors
    (`inheritance_constructors.sol`); C3 order
    (`inheritance_linearization.sol`); `super` and explicit base calls
    (`inheritance_super.sol`, `inheritance_diamond.sol`); and the reported
    or rejected cases (`inheritance_imported.sol`,
    `inheritance_struct_mapping.sol`, `inheritance_shadowed_state.sol`).

---

### Requirement 2 — Soundness corrections

**Modifies:** `REQ-SOL-030` (structs), `REQ-SOL-034` (constant folding),
`REQ-SOL-044` (`require`), `REQ-SOL-048` (`unchecked`), `REQ-SOL-053`
(inline assembly), `REQ-SOL-063` (bitwise operators), `REQ-SOL-070`
(`msg.*`), `REQ-SOL-078` (`selfdestruct` as a no-op), `REQ-SPEC-023`
(quantifiers), `REQ-SPEC-028` (specification arithmetic); narrows
`GAP-010`.

**User Story:** As a developer relying on a proof, I want every construct
the translator accepts to mean what it means in Solidity, so that a proven
property is true of the deployed contract.

**Context.** Each criterion corrects a translation under which a false
property was proven; `test/examples/` has a fixture with a true and a false
property for each.

#### Acceptance Criteria

1. REQ-NEXT-SOL-030. IF a contract invariant mentions `msg.sender` or
   `msg.value`, as for `block.*` and `tx.*`, THEN THE Solidity_Translator
   SHALL fail with an `unsupported` error: they change between transactions.
2. REQ-NEXT-SOL-031. THE Solidity_Translator SHALL evaluate every argument
   of `require`, the message included, with its effects, before the
   condition is assumed.
3. REQ-NEXT-SPEC-010. THE Spec_Parser SHALL bind a quantified variable to
   the values of its declared type: `forall v : T :: P` as
   `forall v :: inRange_T(v) ==> P`, and `exists v : T :: P` as
   `exists v :: inRange_T(v) && P`.
4. REQ-NEXT-SOL-032. THE Solidity_Translator SHALL give the result of a
   bitwise operator the range of the operation's type (signed results may
   be negative), and SHALL compute `~x` exactly (`-x - 1`, or
   `2^n - 1 - x` for `uintn`).
5. REQ-NEXT-SOL-033. THE Solidity_Translator SHALL give a constant
   expression the value solc computes: with rational intermediate values,
   units (`2.5 ether`) and exponents (`1e18`).
6. REQ-NEXT-SOL-034. WHERE `unchecked` applies, THE Solidity_Translator
   SHALL wrap a signed division (`type(int8).min / -1`) and a power of
   constants into the operation's type.
7. REQ-NEXT-SPEC-011. THE Spec_Parser SHALL read `/` and `%` in a
   specification as Solidity's truncating division and remainder.
8. REQ-NEXT-SOL-035. IF a function has a mapping or array `storage`
   parameter, THEN THE Solidity_Translator SHALL fail with an `unsupported`
   error: the parameter refers to the caller's storage, and the
   translation passes parameters by value.
9. REQ-NEXT-SOL-036. IF a function calls an internal function that may end
   the transaction (`selfdestruct`, assembly `return` or `stop`), THEN THE
   Solidity_Translator SHALL fail with an `unsupported` error. Within the
   function that halts, the halt SHALL end the path.
10. REQ-NEXT-SOL-037. THE Solidity_Translator SHALL copy a struct where
    Solidity copies it (into storage, and from storage or calldata into
    memory: assignments, declarations, arguments and returned values), and
    SHALL make a memory struct passed to an internal function unknown after
    the call.
11. REQ-NEXT-SOL-038. THE Solidity_Translator SHALL read the target of a
    struct storage reference (`Info storage d = data;`) when the read
    runs, and SHALL fail with an `unsupported` error on a write through it.

---

### Requirement 3 — Annotation text

**Modifies:** `REQ-SPEC-003` (the expression text is the rest of the line).

**User Story:** As a developer, I want to comment an annotation on its own
line, as the guide's examples do, without the comment being read as part
of the specification.

#### Acceptance Criteria

1. REQ-NEXT-SPEC-001. THE Spec_Parser SHALL end the text of an annotation
   at the first `//` after its keyword. An annotation whose text is empty
   then is reported as unrecognized, as before.
2. REQ-NEXT-SPEC-002. THE Spec_Parser SHALL tokenize the text by
   characters, so that non-ASCII text stays whole, and SHALL separate
   tokens at ASCII whitespace and at no-break spaces (U+00A0).

---

### Requirement 4 — The command line, exit status and plain text

**Modifies:** `REQ-CLI-001`, `REQ-CLI-002` (input and usage),
`REQ-CLI-050`, `REQ-CLI-051`, `REQ-PBT-007` (exit codes), `REQ-OUT-011`,
`REQ-OUT-013` (plain-text sections and summary).

**User Story:** As a developer running StrataSolidity in CI, I want the
documented options and exit status to be the ones the binary has.

#### Acceptance Criteria

1. REQ-NEXT-CLI-001. THE StrataSolidity_Binary SHALL accept a `.sol` file,
   compiled with `solc --standard-json` and parsed in Lean, as its input;
   a `.solidity.st.ion` file (or another input with `--from-sol` absent)
   is read as the legacy Ion format.
2. REQ-NEXT-CLI-002. THE StrataSolidity_Binary's options and environment
   variables SHALL be the `[[flag]]` entries of `docs/capabilities.toml`;
   `scripts/capabilities.py --check` fails when `StrataSolidityMain.lean`
   reads another one, or no longer reads a listed one.
3. REQ-NEXT-CLI-003. IF the input cannot be translated, THEN THE
   StrataSolidity_Binary SHALL exit with code 1 in every output format.
4. REQ-NEXT-CLI-004. WHEN emitting plain text, THE StrataSolidity_Binary
   SHALL exit with code 1 when any obligation is `fail` or a verification
   error, and 0 otherwise. WHEN emitting `--json`, `--sarif` or
   `--pipeline-json`, it SHALL exit with code 0 whatever the verdicts,
   which the consumer of the document judges. This replaces `REQ-CLI-050`,
   `REQ-CLI-051` and `REQ-PBT-007` outside plain text.
5. REQ-NEXT-CLI-005. WHEN `--strict` is given, in every output format, THE
   StrataSolidity_Binary SHALL exit with code 1 when any obligation is not
   `pass`, or an annotation or function was not verified.
6. REQ-NEXT-OUT-001. WHEN emitting plain text and some obligations are
   verification errors, THE StrataSolidity_Binary SHALL list them first,
   under `⚠ Errors (<n>):`, and the summary line SHALL end with
   `, <n> errors`. WHEN annotations or functions were not verified, a last
   line SHALL say how many (`⚠  <n> annotation(s) or function(s) not
   verified (see warnings)`).

---

### Requirement 5 — The in-Lean frontend (decision record)

**Supersedes:** Requirement 8 (`REQ-PY-*`), `REQ-SH-004`, `REQ-SH-006`,
`REQ-SH-007`, `REQ-SH-008`, `REQ-SH-010`, `REQ-CLI-031`, `REQ-CLI-060`.

**Context.** The baseline describes a Python frontend (`solast.py`) that
serialized solc's AST to Ion for the Lean translator. It was replaced by
`StrataSolidity/SolcRunner.lean` and `StrataSolidity/SolcAstParser.lean`,
which run `solc --standard-json` and parse its JSON into typed Lean
structures in the `strataSolidity` binary, and the Python sources were
deleted. The plan for that change was kept outside the repository; this
requirement records its outcome.

#### Acceptance Criteria

1. REQ-NEXT-PIPE-001. THE StrataSolidity_Binary SHALL run solc and parse
   its AST itself; no Python is needed to verify a contract (Python is
   used only by CI tooling: the SARIF schema check and the benchmark CSV
   check).
2. REQ-NEXT-PIPE-002. THE Shell_Wrapper (`strata-verify.sh`) SHALL check
   the Strata submodule (`scripts/check-strata.sh`) and then run the
   binary on its arguments, and do nothing else.
3. REQ-NEXT-PIPE-003. Note. Kept on purpose: the Ion reader, for
   `.solidity.st.ion` inputs (REQ-NEXT-CLI-001), and the shell test
   harnesses (`test/run_tests.sh`, `test/run_exit_code_tests.sh`,
   `bench/bench.sh`).

---

### Requirement 6 — Documented capabilities follow from tests

**Extends:** `REQ-DIST-006` (the user guide): its feature pages are generated.

**User Story:** As a user, I want the list of what StrataSolidity supports
to be true of the binary I build, and as a contributor I want a change of
behavior to fail CI until the documentation says so.

#### Acceptance Criteria

1. REQ-NEXT-DIST-001. THE Repository_Documentation SHALL state what is
   verified, partly verified, skipped or rejected in one place: the
   capability ledger `docs/capabilities.toml`, with a status per feature.
2. REQ-NEXT-DIST-002. Every ledger entry SHALL name witnesses: obligations
   of `test/examples/` fixtures as their golden files report them,
   translation errors, warnings, or tests that CI runs; the witnesses
   SHALL fit the status (a verified feature has a proven obligation and a
   refuted or unproven one).
3. REQ-NEXT-DIST-003. The feature tables of `LIMITATIONS.md`, `README.md`,
   `FAQ.md`, the guide (`supported_features.md`, `limitations.md`,
   `first_verification.md`), the gap table below and the landing page
   SHALL be generated from the ledger.
4. REQ-NEXT-DIST-004. CI SHALL run `scripts/capabilities.py --check`, which
   fails when a witness does not hold, a gap's status disagrees with the
   entries citing it, the option or annotation lists differ from the
   code, or a generated table is out of date.
5. REQ-NEXT-TEST-002. Each construct the ledger lists as rejected or
   failing SHALL have a fixture whose golden file pins the error
   (`test/examples/gap_*.sol` when no other fixture shows it), so that
   supporting it changes a golden file and its ledger entry together.
   This replaces the XFAIL registry of `REQ-TEST-016` (`GAP-011`).

---

### Requirement 7 — Gap status

The status of each baseline gap at this revision, generated from the ledger.
A gap is closed only when every entry citing it is verified.

<!-- capabilities:begin gaps -->
<!-- Generated from docs/capabilities.toml by scripts/capabilities.py: edit the ledger, then run the script. -->
| Gap | Baseline | Status | Now |
|---|---|---|---|
| GAP-001 | No counterexample generation | Narrowed | A refuted obligation is reported failed, with a counterexample when z3 gives a model. Unknown results remain for quantified assumptions, nonlinear arithmetic and timeouts. |
| GAP-002 | Struct fields through mappings | Open | A function using a struct-valued mapping (or an array of structs) is not verified, with a warning; a modifier using one stops the translation. |
| GAP-003 | `old()` in loop invariants | Closed | `old(e)` in a loop invariant is the value at the function's entry. |
| GAP-004 | `@custom:strata lemma` is not supported | Open | Reported as an unrecognized annotation, and ignored. |
| GAP-005 | `block.timestamp` modeling | Open | One positive value per transaction; nothing relates transactions. |
| GAP-006 | `msg.sender` in constructors | Closed | `msg.sender` in a constructor is the deployer, and is verified as in any function. |
| GAP-007 | External calls, reentrancy, cross-contract reasoning | Narrowed | A call that may re-enter makes the contract's state unknown except for its invariants, which are checked before the call; `--assume-no-reentrancy` trusts calls not to re-enter. Results of calls are unknown. |
| GAP-008 | Dynamic array `push`/`pop` | Narrowed | `push` on an array state variable is modelled; `pop` stops the translation. |
| GAP-009 | Full multi-contract inheritance with virtual dispatch | Narrowed | Closed by Requirement 1 above, except for bases in another file, arguments in inheritance specifiers, `super` of an overloaded function and redeclared private state variables. |
| GAP-010 | Storage references to struct-through-mapping and to mappings | Open | A reference to a struct state variable can be read (writes through it are rejected); one to a struct in a mapping is not verified, as GAP-002; one to a mapping or an array is rejected. |
| GAP-011 | XFAIL tests | Obsolete | The XFAIL registry and its harness were removed. Known failures are pinned instead by `test/examples/gap_*.sol`, whose golden files hold the current error. |
| GAP-012 | Only z3 wired into the CLI | Open | Unchanged: the solver is z3; the documentation no longer mentions cvc5. |

Limitations without a baseline gap, by capability id:

| Capability | Feature | Status |
|---|---|---|
| `invariant-transaction-values` | `msg.sender`, `msg.value`, `block.*` or `tx.*` in an invariant | ❌ Rejected |
| `modifies-nested-key` | `modifies m[a][b]` (a key with two indexes) | ⚠️ Not verified |
| `loop-heap-frame` | A loop that writes contract state | ⚠️ Partly |
| `exists` | `exists v : T :: P` | ⚠️ Partly |
| `spec-operators-missing` | `**`, bitwise and shift operators in specifications | ❌ Rejected |
| `spec-conversion` | Type conversions in specifications (`uint8(x)`) | ❌ Fails |
| `annotation-misuse` | Misspelled, misplaced or multi-line annotations | ⚠️ Not verified |
| `overload-types` | Overloads that differ only between integer and address parameters (`f(uint256)`, `f(address)`) | ❌ Fails |
| `revert-call` | `revert("reason")`, `revert()` | ❌ Fails |
| `constructor-internal-call` | A constructor that calls an internal function using state (`_mint` in a constructor) | ❌ Rejected |
| `halting-calls` | Calling a function that may end the transaction (`selfdestruct`, assembly `return` or `stop`) | ❌ Rejected |
| `libraries` | Library calls (`L.f(x)`, `using L for T`) | ❌ Fails |
| `file-level-functions` | Functions declared outside a contract | ❌ Fails |
| `checked-overflow` | Checked arithmetic (outside `unchecked`) | ⚠️ Partly |
| `power-variable` | `**` with an operand that is not a constant | ❌ Rejected |
| `bitwise` | Bitwise operators and shifts | ⚠️ Partly |
| `enums` | Enums | ⚠️ Partly |
| `string-bytes` | `string` and dynamic `bytes` values | ❌ Fails |
| `hashes` | `keccak256`, `sha256`, `abi.encode`, `abi.encodePacked` | ⚠️ Partly |
| `abi-functions` | `abi.encodeWithSelector` or `abi.encodeWithSignature` with arguments, `abi.encodeCall`, `abi.decode`, more arguments than above | ❌ Fails |
| `delete-non-integer` | `delete` of a `bool`, an array or a struct | ❌ Fails |
| `array-index-range` | An array index out of range | ⚠️ Partly |
| `array-push-nested` | `push` on an array in a mapping or a struct, or through a returned storage reference | ❌ Fails |
| `new-array-length` | `.length` of a memory array created with `new` | ❌ Fails |
| `structs` | Structs | ⚠️ Partly |
| `struct-positional` | A struct built with positional arguments (`Info(1, 2)`) | ❌ Fails |
| `storage-params` | A mapping or array `storage` parameter | ❌ Rejected |
| `branch-types` | An `if`/`else` or `try`/`catch` whose branches end with assignments of different types | ❌ Fails |
| `operand-order` | An operand that changes a variable another operand reads (`_inc() + x`) | ❌ Rejected |
| `tuple-assignment` | Assigning a tuple to existing variables (`(a, b) = (b, a)`) | ❌ Rejected |
| `result-name` | A parameter or local named `result` in a function whose return value is unnamed | ❌ Fails |
| `msg-value-nonpayable` | `msg.value` in a function that is not `payable` | ⚠️ Partly |
| `gasleft-balances` | `gasleft()`, `address.balance`, the result of `send` | ⚠️ Unknown values |
| `assembly` | Inline assembly | ⚠️ Unknown values |
<!-- capabilities:end gaps -->
