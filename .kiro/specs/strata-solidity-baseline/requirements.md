# Requirements Document

## Introduction

This document is the **retrospective baseline** for StrataSolidity as it exists on the current `main` branch. It specifies, as verifiable requirements, every capability, annotation, CLI flag, output format, and tracked gap that the codebase exhibits today. It introduces no new behavior.

The baseline has three consumers:

1. A stable reference that the follow-on spec `strata-solidity-next` diffs against line-by-line. Every capability, flag, annotation, and gap carries a stable ID of the form `REQ-<CATEGORY>-<NNN>` or `GAP-<NNN>` so that future specs can cite them unambiguously.
2. A characterization surface for property-based tests that pin down today's behavior (the `Correctness Properties` section).
3. A conformity reference for the Strata front-end (sibling-path dependency on `../Strata`).

Scope boundary. This document describes the current Solidity subset, specification language, pipeline stages, CLI surface, Python tooling, output formats, test harnesses, distribution packaging, and known gaps. It does not propose changes, does not define acceptance for new features, and does not re-specify Strata Core or Laurel. Where the checked-in documentation disagrees with the compiled code, the code wins and the disagreement is surfaced as an acceptance-criterion note.

Relationship to Strata. The project depends on a sibling checkout at `../Strata` via a Lake `path` require. Python helpers expect `../Strata/Tools/Python` on `PYTHONPATH`. The Laurel dialect is targeted (not Core directly, not C_Simp). Moving, symlinking, or modifying `../Strata` is out of scope for this baseline.

Relationship to `strata-solidity-next`. The `Current Gaps` section enumerates every tracked limitation with its root cause and, where available, its Asana ticket. `strata-solidity-next` closes one or more of these gaps; it must cite the gap IDs it targets and must leave the other baseline requirements unchanged.

## Glossary

- **StrataSolidity**: The Lean 4 package and CLI binary providing the Solidity front-end to the Strata verification framework.
- **Strata**: The verification framework that StrataSolidity depends on, located at `../Strata` relative to the project root. Provides Laurel, Core, VCG, and the SMT encoder.
- **Laurel**: High-level intermediate verification language in Strata. Target dialect of StrataSolidity's translation. Preserves structured control flow, heap-allocated objects, and fields.
- **Core**: Low-level verification language in Strata, roughly equivalent to Boogie. Laurel is translated to Core during verification. Flat procedures, explicit `spec {}` blocks, maps with `select`/`update`.
- **Ion**: Binary/textual serialization format used to exchange AST data between the Python front-end (`solast.py`) and the Lean binary.
- **DDM**: Strata's dialect-driven metamodel. `Strata.Solidity.Command SourceRange` is the DDM AST type that `ReadSolidity` produces from Ion input.
- **solast**: Python module (`Tools/Solidity/src/solast.py`) that converts solc's JSON AST into Ion, using a dialect descriptor.
- **solc**: The upstream Solidity compiler. Used for AST extraction only.
- **VCG**: Verification Condition Generator in Strata Core. Produces one SMT query per `assert` and per `ensures` clause.
- **Obligation**: A single proof obligation produced by the VCG. Carries a `label`, a source `metadata` record, and an `Outcome` (`pass`, `fail`, `unknown`, `implementationError`).
- **NatSpec**: Solidity's native structured documentation format (`///` and `/** */`). StrataSolidity specifications live inside NatSpec comments.
- **`@custom:strata`**: The NatSpec custom tag used by every StrataSolidity annotation.
- **SARIF**: Static Analysis Results Interchange Format. StrataSolidity emits SARIF 2.1.0 with `--sarif`.
- **XFAIL**: A test expected to fail; listed in `known_failures.txt`.
- **TransCtx**: Translation context threaded through `SolToLaurel` during AST→Laurel lowering.
- **Heap parameterization**: The Core transformation that flattens Laurel heap objects and fields into explicit map parameters.
- **mbqi**: Model-based quantifier instantiation in z3.
- **GAP**: Tracked limitation bridging to `strata-solidity-next`.

---

## Requirements

### Requirement 1 — Project Identity and Metadata

**User Story:** As a consumer of this baseline, I want the project identity, toolchain, and licensing pinned, so that `strata-solidity-next` starts from known coordinates.

#### Acceptance Criteria

1. THE StrataSolidity_Project SHALL declare its Lake package name as `StrataSolidity` in `lakefile.toml`.
2. THE StrataSolidity_Project SHALL declare its package version as `0.1.0` in `lakefile.toml`.
3. THE StrataSolidity_Project SHALL declare default targets `StrataSolidity` and `strataSolidity` in `lakefile.toml`.
4. THE StrataSolidity_Project SHALL declare `testDriver = "StrataSolidityTest"` in `lakefile.toml`.
5. THE StrataSolidity_Project SHALL pin the Lean toolchain to `leanprover/lean4:v4.27.0` in `lean-toolchain`.
6. THE StrataSolidity_Project SHALL be licensed under `Apache-2.0 OR MIT` as recorded in the source-file SPDX headers.

---

### Requirement 2 — Strata Framework Contract (REQ-STRATA-*)

**User Story:** As the consumer of the `../Strata` sibling package, I want the path-require contract pinned, so that the framework is neither relocated nor version-drifted.

#### Acceptance Criteria

1. REQ-STRATA-001. THE `lakefile.toml` SHALL contain a `[[require]]` entry with `name = "Strata"` and `path = "../Strata"`.
2. REQ-STRATA-002. THE `lake-manifest.json` SHALL list `Strata` with `"type": "path"` and `"dir": "../Strata"`.
3. REQ-STRATA-003. WHEN `strata-verify.sh` runs, THE Shell_Wrapper SHALL set `PYTHONPATH` to include `$PROJECT_DIR/../Strata/Tools/Python` before invoking `src.solast`.
4. REQ-STRATA-004. THE Translation_Pipeline SHALL target the Laurel dialect of Strata and SHALL NOT target Core directly or C_Simp.
5. REQ-STRATA-005. THE StrataSolidity_Project SHALL treat `../Strata` as external and SHALL NOT require `../Strata` to be moved, symlinked, or modified for this baseline.

---

### Requirement 3 — Supported Solidity Subset (REQ-SOL-*)

**User Story:** As the author of a Solidity contract, I want an exhaustive enumeration of supported language features, so that I know exactly which constructs the current pipeline accepts.

#### Acceptance Criteria — Contract-level

1. REQ-SOL-001. THE Solidity_Translator SHALL accept `contract` declarations.
2. REQ-SOL-002. THE Solidity_Translator SHALL accept `interface` declarations.
3. REQ-SOL-003. THE Solidity_Translator SHALL accept `abstract contract` declarations.
4. REQ-SOL-004. THE Solidity_Translator SHALL accept single inheritance via `is`.
5. REQ-SOL-005. THE Solidity_Translator SHALL accept diamond (multiple) inheritance via the solc AST `baseContracts` field, flattened at the AST level.
6. REQ-SOL-006. WHERE inheritance produces virtual dispatch across contracts, THE Solidity_Translator SHALL cover the single-contract case only (see GAP-009).

#### Acceptance Criteria — Functions, constructors, special receivers

7. REQ-SOL-010. THE Solidity_Translator SHALL accept functions with visibility `public`, `external`, `internal`, and `private`.
8. REQ-SOL-011. THE Solidity_Translator SHALL accept `view` and `pure` state mutability markers.
9. REQ-SOL-012. THE Solidity_Translator SHALL accept `constructor()` declarations and SHALL check contract invariants as constructor postconditions.
10. REQ-SOL-013. THE Solidity_Translator SHALL accept `receive()` external payable functions.
11. REQ-SOL-014. THE Solidity_Translator SHALL accept `fallback()` external functions.
12. REQ-SOL-015. THE Solidity_Translator SHALL accept modifiers with positional arguments.
13. REQ-SOL-016. WHEN a modifier is applied to a function, THE Solidity_Translator SHALL inline the modifier body at the `_` placeholder and SHALL lift any pre-`_` `require` calls into preconditions of the wrapped function.

#### Acceptance Criteria — Types

14. REQ-SOL-020. THE Solidity_Translator SHALL accept `uint` and `int` with bit widths 8, 16, 24, …, 256.
15. REQ-SOL-021. THE Solidity_Translator SHALL accept `bool`.
16. REQ-SOL-022. THE Solidity_Translator SHALL accept `address` and `address payable`.
17. REQ-SOL-023. THE Solidity_Translator SHALL accept `bytes32`.
18. REQ-SOL-024. THE Solidity_Translator SHALL accept `bytes` and `string` dynamic types and SHALL map them internally to `TInt` (sound overapproximation).
19. REQ-SOL-025. THE Solidity_Translator SHALL accept simple mappings of the form `mapping(K => V)`.
20. REQ-SOL-026. THE Solidity_Translator SHALL accept nested mappings of the form `mapping(K1 => mapping(K2 => V))`.
21. REQ-SOL-027. THE Solidity_Translator SHALL accept fixed-size arrays `T[N]` and dynamic arrays `T[]`.
22. REQ-SOL-028. THE Solidity_Translator SHALL accept `.length` on dynamic arrays.
23. REQ-SOL-029. IF a dynamic array `push` or `pop` is encountered, THEN THE Solidity_Translator SHALL NOT model the operation (see GAP-008).
24. REQ-SOL-030. THE Solidity_Translator SHALL accept `struct` declarations.
25. REQ-SOL-031. THE Solidity_Translator SHALL accept `enum` declarations and SHALL model each enum value as a constrained integer.
26. REQ-SOL-032. THE Solidity_Translator SHALL accept user-defined value types declared with `type Name is T`.
27. REQ-SOL-033. THE Solidity_Translator SHALL accept `using A for B` directives.
28. REQ-SOL-034. THE Solidity_Translator SHALL accept `immutable` and `constant` state variables and SHALL constant-fold their values where statically known.
29. REQ-SOL-035. THE Solidity_Translator SHALL accept transient storage state variables (EIP-1153) and SHALL model them identically to regular state variables within a single transaction. Cross-transaction reasoning is out of scope (non-goal).

#### Acceptance Criteria — Statements

30. REQ-SOL-040. THE Solidity_Translator SHALL accept `if`/`else` statements.
31. REQ-SOL-041. THE Solidity_Translator SHALL accept `while` loops.
32. REQ-SOL-042. THE Solidity_Translator SHALL accept `for` loops.
33. REQ-SOL-043. THE Solidity_Translator SHALL accept `return` statements, with and without a value.
34. REQ-SOL-044. THE Solidity_Translator SHALL accept `require(cond)` and `require(cond, msg)` and SHALL treat them as assumptions of `cond` on the continuing path.
35. REQ-SOL-045. THE Solidity_Translator SHALL accept `assert(cond)` and SHALL treat it as a proof obligation.
36. REQ-SOL-046. THE Solidity_Translator SHALL accept `revert()`, `revert(msg)`, and `revert CustomError(args)`.
37. REQ-SOL-047. WHEN `revert` is executed, THE Solidity_Translator SHALL terminate the path without requiring postconditions to hold on the reverted branch.
38. REQ-SOL-048. THE Solidity_Translator SHALL accept `unchecked { … }` blocks and SHALL set an `isInsideUnchecked` context flag that disables overflow checks inside the block.
39. REQ-SOL-049. THE Solidity_Translator SHALL accept `delete x` and SHALL model it as assigning the default zero value for the type of `x`.
40. REQ-SOL-050. THE Solidity_Translator SHALL accept `emit EventName(args)` and SHALL model `emit` as a no-op for verification.
41. REQ-SOL-051. IF a `try { … } catch { … }` statement is encountered, THEN THE Solidity_Translator SHALL skip the statement with a sound overapproximation (havoc of touched state).
42. REQ-SOL-052. IF a multi-component tuple destructuring assignment is encountered, THEN THE Solidity_Translator SHALL apply a sound overapproximation.
43. REQ-SOL-053. IF inline assembly (`assembly { … }`) is encountered, THEN THE Solidity_Translator SHALL havoc all state variables that the block touches.

#### Acceptance Criteria — Expressions

44. REQ-SOL-060. THE Solidity_Translator SHALL accept arithmetic operators `+`, `-`, `*`, `/`, `%`, and `**`.
45. REQ-SOL-061. THE Solidity_Translator SHALL accept comparison operators `==`, `!=`, `>=`, `<=`, `>`, and `<`.
46. REQ-SOL-062. THE Solidity_Translator SHALL accept boolean operators `&&`, `||`, and `!`.
47. REQ-SOL-063. THE Solidity_Translator SHALL accept bitwise operators `&`, `|`, `^`, `~`, `<<`, and `>>` as uninterpreted functions.
48. REQ-SOL-064. THE Solidity_Translator SHALL accept the ternary operator `cond ? a : b`.
49. REQ-SOL-065. THE Solidity_Translator SHALL accept index access `x[k]` on arrays and mappings.
50. REQ-SOL-066. THE Solidity_Translator SHALL accept member access `x.y`.
51. REQ-SOL-067. THE Solidity_Translator SHALL accept type casts including `address(expr)`, `payable(expr)`, `uint256(expr)`, and `int256(expr)`.
52. REQ-SOL-068. THE Solidity_Translator SHALL treat `address(expr)` as the identity on already-address-typed values.

#### Acceptance Criteria — EVM globals, builtins, and calls

53. REQ-SOL-070. THE Solidity_Translator SHALL model `msg.sender`, `msg.value`, `msg.data`, and `msg.sig` as implicit function parameters.
54. REQ-SOL-071. THE Solidity_Translator SHALL model `block.number`, `block.timestamp`, `block.chainid`, `tx.origin`, and `gasleft()` as nondeterministic constants per call.
55. REQ-SOL-072. THE Solidity_Translator SHALL model `address.balance`, `address.code`, and `address.codehash` as nondeterministic values.
56. REQ-SOL-073. THE Solidity_Translator SHALL model `keccak256`, `sha256`, and the `abi.encode*` family as uninterpreted functions with the standard congruence axiom.
57. REQ-SOL-074. WHERE a `keccak256(abi.encodePacked(...))` expression is used as a mapping key, THE Solidity_Translator SHALL accept it.
58. REQ-SOL-075. THE Solidity_Translator SHALL accept `type(T).max` and `type(T).min` for integer types `T` and SHALL constant-fold them.
59. REQ-SOL-076. IF a `call`, `delegatecall`, `staticcall`, `transfer`, or `send` is encountered, THEN THE Solidity_Translator SHALL model the call as nondeterministic (return value and touched external state havoced).
60. REQ-SOL-077. IF a `new Contract(args)` expression is encountered, THEN THE Solidity_Translator SHALL accept it with a nondeterministic returned address; see GAP-007 for cross-contract reasoning.
61. REQ-SOL-078. IF `selfdestruct(addr)` is encountered, THEN THE Solidity_Translator SHALL model it as a no-op.
62. REQ-SOL-079. THE Solidity_Translator SHALL accept array slices and SHALL model them nondeterministically.

#### Acceptance Criteria — Automatic state-variable conventions

63. REQ-SOL-090. WHEN a `mapping(K => V)` state variable `m` is lowered to Laurel, THE Solidity_Translator SHALL expose an input parameter `m_in : Map[K, V]` and an output parameter `m : Map[K, V]`.
64. REQ-SOL-091. WHEN a scalar state variable `s` is lowered to Laurel, THE Solidity_Translator SHALL expose an input parameter `__old_s` and an output parameter `s`.
65. REQ-SOL-092. WHEN a constructor is lowered, THE Solidity_Translator SHALL expose state variables as output parameters only and SHALL zero-initialize all fields on entry.

#### Note on documentation vs code

66. REQ-SOL-100. THE Repository_Documentation refers to the annotation tag as `@custom:strata`. `LIMITATIONS.md` uses `@strata` in some examples. THE Code_Parser in `SpecParser.lean` SHALL accept only `@custom:strata` (optionally preceded by `* ` inside multi-line comments). This disagreement SHALL be recorded as a documentation-only defect, not a capability of the pipeline.

---

### Requirement 4 — Specification Language (REQ-SPEC-*)

**User Story:** As an annotation author, I want the exact grammar, placement rules, and semantics of `@custom:strata` annotations pinned, so that any future change is a discrete diff against this baseline.

#### Acceptance Criteria — Syntactic form

1. REQ-SPEC-001. THE Spec_Parser SHALL recognize annotations only inside Solidity NatSpec comments, starting with `///` (single-line) or `/** */` (multi-line).
2. REQ-SPEC-002. THE Spec_Parser SHALL recognize the line prefix `@custom:strata ` (with or without a leading `* ` for multi-line comments) and SHALL NOT recognize any other tag.
3. REQ-SPEC-003. THE Spec_Parser SHALL treat the remainder of the line following the keyword as the expression text, after trimming ASCII whitespace.
4. REQ-SPEC-004. THE Spec_Parser SHALL recognize exactly the following keywords, and reject any other trailing keyword: `requires`, `ensures`, `invariant`, `modifies`, `loop-invariant`.
5. REQ-SPEC-005. THE Spec_Parser SHALL recognize the quantifier forms `forall v : T :: body` and `exists v : T :: body` as expressions within any of the five keyword contexts.

#### Acceptance Criteria — Placement rules

6. REQ-SPEC-010. THE Spec_Parser SHALL require `requires`, `ensures`, `modifies`, and `loop-invariant` annotations to be attached to the NatSpec block immediately preceding a function declaration.
7. REQ-SPEC-011. THE Spec_Parser SHALL require `invariant` annotations to be attached to the NatSpec block immediately preceding a state-variable declaration inside a contract.
8. REQ-SPEC-012. THE Spec_Parser SHALL NOT recognize `invariant` placed on a contract or function declaration.

#### Acceptance Criteria — Expression grammar

9. REQ-SPEC-020. THE Spec_Expression_Grammar SHALL include identifiers, integer literals (including scientific notation like `1e24`), `true`, and `false`.
10. REQ-SPEC-021. THE Spec_Expression_Grammar SHALL include `old(expr)` for pre-state values.
11. REQ-SPEC-022. THE Spec_Expression_Grammar SHALL include `sum(mapping)` with update-axiom semantics as defined in `docs/ir-reference.md`.
12. REQ-SPEC-023. THE Spec_Expression_Grammar SHALL include `forall v : T :: body` and `exists v : T :: body` over Solidity types.
13. REQ-SPEC-024. THE Spec_Expression_Grammar SHALL include the implication operator `a ==> b` with right precedence below boolean `&&`/`||`.
14. REQ-SPEC-025. THE Spec_Expression_Grammar SHALL include `type(T).max` and `type(T).min` for integer types `T`.
15. REQ-SPEC-026. THE Spec_Expression_Grammar SHALL include `keccak256(abi.encodePacked(a, b))` as a key expression.
16. REQ-SPEC-027. THE Spec_Expression_Grammar SHALL include `msg.sender`, `msg.value`, and `address(0)`.
17. REQ-SPEC-028. THE Spec_Expression_Grammar SHALL include arithmetic `+`, `-`, `*`, `/`, `%`.
18. REQ-SPEC-029. THE Spec_Expression_Grammar SHALL include comparison operators `==`, `!=`, `>=`, `<=`, `>`, `<`.
19. REQ-SPEC-030. THE Spec_Expression_Grammar SHALL include boolean `&&`, `||`, and `!`.

#### Acceptance Criteria — `modifies` patterns

20. REQ-SPEC-040. THE Spec_Parser SHALL accept `modifies var` (whole variable).
21. REQ-SPEC-041. THE Spec_Parser SHALL accept `modifies m[k]` (single-key mapping pattern).
22. REQ-SPEC-042. THE Spec_Parser SHALL accept `modifies m[k1], m[k2]` (multi-key mapping patterns, comma-separated).
23. REQ-SPEC-043. THE Spec_Parser SHALL accept `modifies a, b, c` (multiple variables, comma-separated).
24. REQ-SPEC-044. WHEN a `modifies` clause is omitted, THE Verification_Pipeline SHALL NOT emit frame obligations for that function.
25. REQ-SPEC-045. WHEN a `modifies` clause is present, THE Verification_Pipeline SHALL emit a frame obligation requiring every unlisted state variable and every unlisted mapping key to be equal to its pre-state value.
26. REQ-SPEC-046. WHEN `modifies m[k]` appears, THE Verification_Pipeline SHALL generate a universal frame condition `forall __k :: __k != k ==> select(m, __k) == select(m_in, __k)`.

#### Acceptance Criteria — Automatic assumptions

27. REQ-SPEC-050. THE Verification_Pipeline SHALL assume `v >= 0` for every unsigned integer parameter and state variable `v`.
28. REQ-SPEC-051. THE Verification_Pipeline SHALL assume `msg.sender > 0` (the zero address cannot send transactions).
29. REQ-SPEC-052. THE Verification_Pipeline SHALL assume `msg.value >= 0`.
30. REQ-SPEC-053. WHEN `emit` is executed, THE Verification_Pipeline SHALL treat the statement as a no-op with respect to specifications.
31. REQ-SPEC-054. WHEN `revert` is executed, THE Verification_Pipeline SHALL NOT require postconditions to hold on the reverted path; postconditions apply only on non-reverting paths.

#### Acceptance Criteria — Constructor semantics

32. REQ-SPEC-060. WHEN a constructor is verified, THE Verification_Pipeline SHALL treat contract invariants as postconditions that the constructor must establish.
33. REQ-SPEC-061. THE Verification_Pipeline SHALL NOT introduce a `self` input for a constructor and SHALL NOT accept `modifies self` inside one.
34. REQ-SPEC-062. WHEN a constructor is verified, THE Verification_Pipeline SHALL expose state variables as output parameters.
35. REQ-SPEC-063. IF `msg.sender` appears inside a constructor body, THEN THE Verification_Pipeline SHALL NOT produce a sound model (see GAP-006).

#### Acceptance Criteria — Aggregate operators

36. REQ-SPEC-070. WHEN `sum(m)` appears for a mapping `m : Map[K, int]`, THE Verification_Pipeline SHALL introduce an uninterpreted function `sum_m` plus the update axiom `forall m, k, v :: sum_m(update(m, k, v)) == sum_m(m) - select(m, k) + v` as described in `docs/ir-reference.md`.

---

### Requirement 5 — Pipeline Contract (REQ-PIPE-*)

**User Story:** As a downstream tool, I want the pipeline stages and their interfaces pinned, so that intermediate artifacts remain consumable.

#### Acceptance Criteria

1. REQ-PIPE-001. Stage 1 (Parsing): THE Python_Toolchain SHALL invoke `solc --ast-json` and pass the AST through `solast.py sol_to_strata` to produce a `*.solidity.st.ion` file.
2. REQ-PIPE-002. Stage 2 (Reading): THE Lean_Pipeline SHALL read the Ion file via `Strata.Solidity.ReadSolidity` and produce a value of type `Array (Strata.Solidity.Command SourceRange)`.
3. REQ-PIPE-003. Stage 3 (Lowering): THE Lean_Pipeline SHALL translate the Solidity DDM command to Laurel via `Strata.Solidity.solidityToLaurel`.
4. REQ-PIPE-004. Stage 4 (Laurel→Core): THE Lean_Pipeline SHALL translate the Laurel program to Core via `Strata.Laurel.translate`, retaining any modifies diagnostics produced.
5. REQ-PIPE-005. Stage 5 (Verification): THE Lean_Pipeline SHALL invoke `Core.verify` to generate VCs and dispatch SMT queries to the configured solver.
6. REQ-PIPE-006. WHEN the loaded Ion file contains more than one `SourceUnit` `Command` or fewer than one, THE StrataSolidity_Binary SHALL terminate with an error `"Expected exactly one SourceUnit command, got <N>"` and exit non-zero.
7. REQ-PIPE-007. THE Lean_Pipeline SHALL target the Laurel dialect (rationale: Laurel handles heap parameterization for OOP-like storage).
8. REQ-PIPE-008. IF `Strata.Solidity.solidityToLaurel` returns `.error e`, THEN THE StrataSolidity_Binary SHALL terminate with `"Solidity to Laurel translation failed: {e}"` and exit non-zero.
9. REQ-PIPE-009. IF `Strata.Laurel.translate` returns `.error diagnostics`, THEN THE StrataSolidity_Binary SHALL terminate with `"Laurel to Core translation failed: {diagnostics}"` and exit non-zero.

---

### Requirement 6 — CLI Binary `strataSolidity` (REQ-CLI-*)

**User Story:** As a developer or CI runner, I want the Lean CLI binary's usage, flags, environment variables, output precedence, and exit-code contract pinned, so that scripts that consume it remain stable.

#### Acceptance Criteria — Usage and argument handling

1. REQ-CLI-001. THE StrataSolidity_Binary SHALL accept invocation of the form `strataSolidity <file.solidity.st.ion> [flags…]`.
2. REQ-CLI-002. IF zero or more than one non-flag argument is provided, THEN THE StrataSolidity_Binary SHALL print `Usage: strataSolidity <file.solidity.st.ion> [--verbose] [--sarif] [--json]` to stderr and exit with code 1.
3. REQ-CLI-003. THE StrataSolidity_Binary SHALL be built by `lake build` and SHALL be located at `.lake/build/bin/strataSolidity` after a successful build.

#### Acceptance Criteria — Flags

4. REQ-CLI-010. THE StrataSolidity_Binary SHALL accept `--verbose`.
5. REQ-CLI-011. THE StrataSolidity_Binary SHALL accept `--sarif`.
6. REQ-CLI-012. THE StrataSolidity_Binary SHALL accept `--json`.
7. REQ-CLI-013. THE StrataSolidity_Binary SHALL accept `--pipeline-json`.
8. REQ-CLI-014. THE StrataSolidity_Binary SHALL accept `--array-theory`.
9. REQ-CLI-015. THE StrataSolidity_Binary SHALL accept `--timeout=N` where `N` is a natural number of seconds; the default is 10.
10. REQ-CLI-016. THE StrataSolidity_Binary SHALL accept `--dump-vc=DIR` where `DIR` is a directory path that the binary creates if missing.
11. REQ-CLI-017. THE StrataSolidity_Binary SHALL accept `--sol-source=PATH` to override the reconstructed Solidity source path.
12. REQ-CLI-018. IF `--timeout=` is provided without a valid natural number, THEN THE StrataSolidity_Binary SHALL use the default value of 10 seconds.

#### Acceptance Criteria — Environment variables

13. REQ-CLI-020. WHEN `STRATA_SMT_DIR` is set, THE StrataSolidity_Binary SHALL use that directory for SMT artifacts across runs.
14. REQ-CLI-021. WHEN `STRATA_SMT_DIR` is unset and neither `--dump-vc` nor `--pipeline-json` is provided, THE StrataSolidity_Binary SHALL use a per-invocation temporary directory and discard it after the run.
15. REQ-CLI-022. WHEN `--pipeline-json` is provided, THE StrataSolidity_Binary SHALL preserve SMT files in a fixed directory (`/tmp/strata-pipeline-smt` by default, or `STRATA_SMT_DIR` when set).
16. REQ-CLI-023. WHEN the fixed SMT directory is used, THE StrataSolidity_Binary SHALL remove any existing `*.smt2` files from that directory before running.

#### Acceptance Criteria — Solver and source reconstruction

17. REQ-CLI-030. THE StrataSolidity_Binary SHALL set `VerifyOptions.solver := "z3"` for all verification calls.
18. REQ-CLI-031. IF the input file path ends with `.solidity.st.ion`, THEN THE StrataSolidity_Binary SHALL look for a sibling `.sol` file with the same base name for source-location reconstruction.
19. REQ-CLI-032. WHEN `--sol-source=PATH` is provided, THE StrataSolidity_Binary SHALL prefer `PATH` over the auto-detected sibling path.
20. REQ-CLI-033. IF the source file cannot be read, THEN THE StrataSolidity_Binary SHALL continue without source-location reconstruction (source line/column omitted from output).

#### Acceptance Criteria — Output-mode precedence

21. REQ-CLI-040. WHEN multiple output flags are provided, THE StrataSolidity_Binary SHALL apply the precedence `--pipeline-json` > `--sarif` > `--json` > plain text.
22. REQ-CLI-041. WHEN no output flag is provided, THE StrataSolidity_Binary SHALL emit the plain-text format specified in REQ-OUT-010..REQ-OUT-015.

#### Acceptance Criteria — Exit code contract

23. REQ-CLI-050. WHEN any VC result has outcome `fail` or `implementationError`, THE StrataSolidity_Binary SHALL exit with code 1.
24. REQ-CLI-051. WHEN every VC result has outcome `pass` or `unknown`, THE StrataSolidity_Binary SHALL exit with code 0.
25. REQ-CLI-052. Note: `unknown` outcomes do not set a failing exit code; this is intentional until counterexamples are supported (see GAP-001).

#### Acceptance Criteria — Verbose behavior

26. REQ-CLI-060. WHEN `--verbose` is provided, THE StrataSolidity_Binary SHALL print the heading `==== Solidity AST (Ion) loaded ====`.
27. REQ-CLI-061. WHEN `--verbose` is provided, THE StrataSolidity_Binary SHALL print the Laurel program under the heading `==== Laurel Program ====`.
28. REQ-CLI-062. WHEN `--verbose` is provided, THE StrataSolidity_Binary SHALL print the Core program under the heading `==== Core Program ====`.

---

### Requirement 7 — Shell Wrapper `strata-verify.sh` (REQ-SH-*)

**User Story:** As a developer invoking verification, I want a single shell entry point that runs the full pipeline, so that I do not invoke `solast.py` manually.

#### Acceptance Criteria

1. REQ-SH-001. THE Shell_Wrapper SHALL accept invocation `strata-verify.sh <file.sol> [extra-args…]`.
2. REQ-SH-002. IF fewer than one argument is provided, THEN THE Shell_Wrapper SHALL print the usage message `Usage: strata-verify <file.sol> [--sarif] [--verbose]` to stderr and exit 1.
3. REQ-SH-003. IF `<file.sol>` does not exist, THEN THE Shell_Wrapper SHALL print `Error: <path> not found` to stderr and exit 1.
4. REQ-SH-004. IF `Tools/Solidity/dialects/Solidity.dialect.st.ion` does not exist, THEN THE Shell_Wrapper SHALL print `Error: Dialect not found at <path>. Run gen_dialect.sh first.` and exit 1.
5. REQ-SH-005. IF `.lake/build/bin/strataSolidity` does not exist, THEN THE Shell_Wrapper SHALL print `Error: strataSolidity not built. Run 'lake build' in <project> first.` and exit 1.
6. REQ-SH-006. WHEN all prerequisites pass, THE Shell_Wrapper SHALL create a temporary directory, run `python3 -m src.solast sol_to_strata --dialect <dialect> <input.sol> <out.ion>` inside `Tools/Solidity`, and then invoke `.lake/build/bin/strataSolidity <out.ion> <extra-args…>`.
7. REQ-SH-007. WHEN invoking `solast`, THE Shell_Wrapper SHALL set `PYTHONPATH` to include `$PROJECT_DIR/../Strata/Tools/Python` followed by any pre-existing `PYTHONPATH`.
8. REQ-SH-008. IF the `solast` stage fails, THEN THE Shell_Wrapper SHALL print `Error: Failed to parse <input.sol>` to stderr and exit non-zero.
9. REQ-SH-009. THE Shell_Wrapper SHALL forward the exit code of the Lean binary as its own exit code.
10. REQ-SH-010. THE Shell_Wrapper SHALL delete the temporary directory on exit via a `trap` handler.

---

### Requirement 8 — Python Tooling (REQ-PY-*)

**User Story:** As an integrator wanting solc-compatible invocation, I want the Python entry points pinned, so that external tools can call `strata_verify.py` with stable contracts.

#### Acceptance Criteria — File mode

1. REQ-PY-001. THE Python_Verifier SHALL accept `strata_verify.py --file <sol_path> [--sarif] [--fail-under N]`.
2. REQ-PY-002. WHEN `--file` is used, THE Python_Verifier SHALL run the same two-stage pipeline as the shell wrapper (solast then strataSolidity) in a temporary directory.
3. REQ-PY-003. WHEN `--fail-under N` is provided, THE Python_Verifier SHALL invoke `strata_coverage.analyze(sol_path)` and SHALL exit 1 if the reported coverage score is below `N` percent.
4. REQ-PY-004. WHEN `--sarif` is provided in file mode, THE Python_Verifier SHALL parse the stdout of the Lean binary as JSON and return it verbatim as the result payload.

#### Acceptance Criteria — Standard-JSON mode (stdin)

5. REQ-PY-010. WHEN invoked without `--file`, THE Python_Verifier SHALL read a solc standard-JSON document from stdin.
6. REQ-PY-011. IF the stdin document is not valid JSON, THEN THE Python_Verifier SHALL print `{"errors": [{"severity": "error", "message": "Invalid JSON input"}]}` to stdout and return.
7. REQ-PY-012. IF `settings.modelChecker.engine != "strata"`, THEN THE Python_Verifier SHALL print an error envelope `{"errors": [{"severity": "error", "message": "Unsupported engine: <engine>. Use 'strata'."}]}` and return.
8. REQ-PY-013. WHEN `settings.modelChecker.timeout` is present, THE Python_Verifier SHALL pass the value as the verification timeout.
9. REQ-PY-014. WHEN `settings.modelChecker.targets` is present, THE Python_Verifier SHALL pass the value through into the output as `modelCheckerTargets`.
10. REQ-PY-015. WHEN `settings.modelChecker.contracts` is present, THE Python_Verifier SHALL log `settings.modelChecker.contracts filtering is not yet supported; all contracts will be verified` at WARNING level and SHALL verify all contracts.
11. REQ-PY-016. WHEN `settings.modelChecker.solvers` is present, THE Python_Verifier SHALL use the first entry; if it is not `"z3"`, THE Python_Verifier SHALL log a warning and default to `z3`.

#### Acceptance Criteria — Output envelope

12. REQ-PY-020. THE Python_Verifier SHALL emit a JSON object of the form `{"errors": [ … ]}`.
13. REQ-PY-021. Each entry SHALL be an object with `severity`, optional `type`, and `message`.
14. REQ-PY-022. Outcome-to-severity mapping SHALL be: lines containing `✅ pass` → `{severity: "warning", type: "Info", message: "Strata: <line>"}`; lines containing `❌ fail` → `{severity: "error", message: "Strata: <line>"}`; lines containing `🟡 unknown` → `{severity: "warning", message: "Strata: <line>"}`.
15. REQ-PY-023. IF parsing stdin succeeds but verification times out, THEN THE Python_Verifier SHALL emit `{"errors": [{"severity": "warning", "message": "Verification timed out"}]}`.
16. REQ-PY-024. IF the Lean binary exits non-zero and produces no stdout, THEN THE Python_Verifier SHALL emit `{"errors": [{"severity": "error", "message": "<stderr>"}]}`.
17. REQ-PY-025. IF the `solast` stage fails in file mode, THEN THE Python_Verifier SHALL emit `{"errors": [{"severity": "error", "message": "Parse failed: <stderr>"}]}`.

#### Acceptance Criteria — solast and dialect helpers

18. REQ-PY-030. THE Python_Toolchain SHALL expose the subcommand `solast.py sol_to_strata --dialect <ion> <in.sol> <out.ion>` as the sole canonical Solidity-to-Ion converter.
19. REQ-PY-031. THE Python_Toolchain SHALL expose `gen_dialect.sh` (or `python3 -m src.solast dialect <DIR>`) to regenerate `Solidity.dialect.st.ion`.
20. REQ-PY-032. THE `strata_verify.py` script SHALL be runnable as `python3 -m src.strata_verify` from `Tools/Solidity`.

---

### Requirement 9 — Output Formats (REQ-OUT-*)

**User Story:** As a CI or IDE integrator, I want every output format's schema pinned, so that parsers and viewers can be built against stable shapes.

#### Acceptance Criteria — Plain text

1. REQ-OUT-010. WHEN emitting plain text, THE StrataSolidity_Binary SHALL first print the heading `==== Verification Results ====` on its own line.
2. REQ-OUT-011. WHEN emitting plain text, THE StrataSolidity_Binary SHALL group obligations into three sections in this order: `❌ Failures (<n>):`, `❓ Unknown (<n>):`, `✅ Passed (<n>):`.
3. REQ-OUT-012. WHEN emitting plain text, THE StrataSolidity_Binary SHALL list each obligation on its own indented line as `  <label>[ at line <L>, col <C>]`.
4. REQ-OUT-013. WHEN emitting plain text, THE StrataSolidity_Binary SHALL emit a final summary line `N passed, M failed, K unknown out of T total`.
5. REQ-OUT-014. WHEN a failing obligation has a non-empty solver counterexample model, THE StrataSolidity_Binary SHALL render each entry as `        <varName> = <value>`, indented eight spaces, one per line, immediately below the obligation line.
6. REQ-OUT-015. Note. Counterexample entries are populated only when the solver returns a model, which is rare under the current configuration (see GAP-001).

#### Acceptance Criteria — `--json`

7. REQ-OUT-020. WHEN `--json` is active, THE StrataSolidity_Binary SHALL emit a single JSON array on stdout.
8. REQ-OUT-021. Each array element SHALL be an object with field `name: string` (obligation label).
9. REQ-OUT-022. Each array element SHALL be an object with field `status: "pass" | "fail" | "unknown" | "implementation_error"`.
10. REQ-OUT-023. WHEN a source position has been resolved, each object SHALL additionally include `line: number` and `col: number`.

#### Acceptance Criteria — `--sarif`

11. REQ-OUT-030. WHEN `--sarif` is active, THE StrataSolidity_Binary SHALL emit a SARIF 2.1.0 top-level object on stdout.
12. REQ-OUT-031. THE SARIF output SHALL be produced by `StrataSolidity.Sarif.toSarif` and SHALL include the obligations list mapped to `results[]`.

#### Acceptance Criteria — `--pipeline-json`

13. REQ-OUT-040. WHEN `--pipeline-json` is active, THE StrataSolidity_Binary SHALL emit a JSON object with top-level fields `laurel`, `core`, `obligations`, and `summary`.
14. REQ-OUT-041. THE `laurel` field SHALL be a string containing the rendered Laurel program.
15. REQ-OUT-042. THE `core` field SHALL be a string containing the rendered Core program.
16. REQ-OUT-043. THE `obligations` field SHALL be an array where each entry has `label: string`, `status: "pass" | "fail" | "unknown"`, `smt: string`, and `smtResult: "unsat" | "sat" | "unknown"`.
17. REQ-OUT-044. THE `summary` field SHALL be an object with integer fields `total`, `passed`, `failed`, `unknown`.
18. REQ-OUT-045. WHEN an obligation's SMT file cannot be read, THE StrataSolidity_Binary SHALL emit an empty string for `smt` rather than failing.

---

### Requirement 10 — Test Suite (REQ-TEST-*)

**User Story:** As a maintainer, I want the test harnesses, golden formats, and XFAIL policy pinned, so that regressions are detected by equality.

#### Acceptance Criteria — Lean unit tests

1. REQ-TEST-001. THE Lean_Test_Driver SHALL be named `StrataSolidityTest` (configured in `lakefile.toml`).
2. REQ-TEST-002. THE Lean_Test_Driver SHALL aggregate `StrataSolidityTest.Solidity.TypesTest`, `StrataSolidityTest.Solidity.SpecParserTest`, and `StrataSolidityTest.Solidity.SpecRewriterTest` via `StrataSolidityTest.lean`.
3. REQ-TEST-003. THE Lean_Test_Driver SHALL be runnable via `lake test`.

#### Acceptance Criteria — Primary golden harness

4. REQ-TEST-010. THE Golden_Harness SHALL be `StrataSolidityTest/Solidity/run_sol_analyze_laurel.sh`.
5. REQ-TEST-011. THE Golden_Harness SHALL iterate every `tests/test_*.sol`, produce an Ion file via `solast sol_to_strata`, run `./.lake/build/bin/strata solAnalyzeLaurel`, and diff the normalized output against `expected/<base>.expected`.
6. REQ-TEST-012. THE Golden_Harness SHALL normalize output by removing internal Lean backtraces and lake path lines, collapsing consecutive blank lines, replacing `Module:<line>:<col>` with `Module:*:*`, replacing `uniqueId := some <n>` with `uniqueId := some <id>`, and stripping multi-line AST dumps following `PANIC ... getType called on`.
7. REQ-TEST-013. THE Golden_Harness SHALL read `known_failures.txt` for XFAIL membership; tests listed there SHALL be reported as `XFAIL` when failing and `XPASS` when unexpectedly passing.
8. REQ-TEST-014. WHEN any test is classified `FAIL` or `XPASS`, THE Golden_Harness SHALL exit with code 1.
9. REQ-TEST-015. WHEN zero tests actually ran (all skipped), THE Golden_Harness SHALL exit with code 1 and print an explanatory error.
10. REQ-TEST-016. The XFAIL registry `known_failures.txt` SHALL currently contain exactly two entries: `test_interface_abstract` and `test_new_expression` (see GAP-011).

#### Acceptance Criteria — Additional golden harness

11. REQ-TEST-020. THE Secondary_Harness SHALL be `test/run_tests.sh`.
12. REQ-TEST-021. THE Secondary_Harness SHALL accept an optional first argument `TIMEOUT` (default 15).
13. REQ-TEST-022. THE Secondary_Harness SHALL iterate `test/examples/*.sol`, run `$STRATA_VERIFY <file> --timeout=$TIMEOUT`, and filter stdout to lines matching `Passed|Failed|Unknown|total|passed` (excluding `PANIC` and `backtrace`).
14. REQ-TEST-023. WHEN an expected file does not exist, THE Secondary_Harness SHALL create it from the filtered output and count the test as `generated`.
15. REQ-TEST-024. WHEN the filtered output equals the expected content, THE Secondary_Harness SHALL count the test as `passed`.

#### Acceptance Criteria — Benchmarks

16. REQ-TEST-030. THE Benchmark_Harness SHALL be `bench/bench.sh` and SHALL accept an optional first argument `TIMEOUT` (default 30).
17. REQ-TEST-031. THE Benchmark_Harness SHALL iterate every `bench/b*.sol`, run `$STRATA_VERIFY <file> --timeout=$TIMEOUT`, and write results to `bench/results.csv`.
18. REQ-TEST-032. THE first line of `bench/results.csv` SHALL be the header `benchmark,functions,specs,state_vars,mappings,status,time_ms,pass,fail,unknown,total` — 11 columns in this exact order.
19. REQ-TEST-033. Each result row SHALL contain 11 comma-separated fields corresponding to the header.
20. REQ-TEST-034. THE `status` field SHALL be one of `ok`, `error`, `timeout`.
21. REQ-TEST-035. THE Benchmark_Harness SHALL emit a final summary line to stdout of the form `OK: n/N | Total: Tms | Avg: Ams | Obligations: P/TOT passed`.
22. REQ-TEST-036. Note. The current `bench/results.csv` contains rows where `state_vars` carries multi-line raw `grep -c` output (embedded newline). This is a known artifact of `grep -c` on inputs without a trailing newline and SHALL be considered a defect of the harness, not a column-count change to the schema.

---

### Requirement 11 — Distribution and Packaging (REQ-DIST-*)

**User Story:** As a user installing StrataSolidity, I want the packaging layout and extension wiring pinned, so that the installation procedure is deterministic.

#### Acceptance Criteria

1. REQ-DIST-001. WHEN `lake build` succeeds, THE Build_System SHALL place the `strataSolidity` binary at `.lake/build/bin/strataSolidity`.
2. REQ-DIST-002. THE VSCode_Kiro_Extension SHALL be installed by symlinking `vscode-strata-solidity` under `~/.kiro/extensions/strata-fv.vscode-strata-solidity-0.2.0`.
3. REQ-DIST-003. THE Install_Procedure SHALL copy `.lake/build/bin/strataSolidity` into `vscode-strata-solidity/bin/`.
4. REQ-DIST-004. THE Install_Procedure SHALL register the extension in `~/.kiro/extensions/extensions.json` with identifier `strata-fv.vscode-strata-solidity`, version `0.2.0`, and the metadata fields documented in `DISTRIBUTION.md`.
5. REQ-DIST-005. THE Kiro_Power SHALL be located at `powers/strata/` for AI-assisted specs.
6. REQ-DIST-006. THE User_Guide SHALL be an mdBook at `docs/guide/` with source under `src/` and build output under `book/`.
7. REQ-DIST-007. THE `docs/guide/src/SUMMARY.md` SHALL be the canonical table of contents for the mdBook.
8. REQ-DIST-008. THE Project SHALL be distributed under `Apache-2.0 OR MIT`.

---

### Requirement 12 — Current Gaps Bridging to `strata-solidity-next` (GAP-*)

**User Story:** As the author of `strata-solidity-next`, I want every tracked limitation enumerated with its root cause and tracking link, so that each follow-on requirement cites exactly one or more GAP IDs.

Each gap is expressed as an unwanted-event requirement (`IF … THEN …`) plus root cause and tracking metadata.

#### Acceptance Criteria

1. GAP-001. No counterexample generation. IF verification cannot prove a postcondition, THEN THE StrataSolidity_Binary SHALL report `unknown` instead of `fail` and SHALL NOT emit concrete variable values. Root cause: z3 model-based quantifier instantiation (mbqi) is disabled because enabling it causes non-termination on the universally quantified Map axioms. Tracking: Asana P0 `1214145784885275`.
2. GAP-002. Struct fields through mappings. IF a specification references a struct field accessed through a mapping value (for example `payments[id].amount`), THEN THE Solidity_Translator SHALL NOT produce a sound Core translation. Root cause: Strata Core HeapParameterization cannot resolve struct field names through composite mapping values. Tracking: Asana P0 `1214065007095245`.
3. GAP-003. `old()` in loop invariants. IF `old(expr)` appears inside a `@custom:strata loop-invariant`, THEN THE Verification_Pipeline SHALL fail to resolve the `__old` marker in the loop context. Root cause: the `__old` marker is not propagated into loop scopes by the current rewriter.
4. GAP-004. `@custom:strata lemma` is not supported. IF a `@custom:strata lemma` annotation is encountered, THEN THE Spec_Parser SHALL reject or ignore it. Root cause: Laurel grammar does not yet expose a lemma construct.
5. GAP-005. `block.timestamp` modeling. IF a specification references `block.timestamp` with temporal meaning (monotonicity across calls, deltas), THEN THE Verification_Pipeline SHALL NOT model the intended semantics. Root cause: no time abstraction is implemented; `block.timestamp` is a nondeterministic constant per call.
6. GAP-006. `msg.sender` in constructors. IF `msg.sender` appears in a constructor body and is constrained by specification, THEN THE Verification_Pipeline SHALL NOT produce a sound model. Root cause: constructor handling is incomplete.
7. GAP-007. External calls, reentrancy, cross-contract reasoning. IF a specification depends on the semantics of `call`/`delegatecall`/`staticcall` beyond a nondeterministic overapproximation, THEN THE Verification_Pipeline SHALL NOT be able to prove it. Root cause: no cross-contract reasoning is implemented.
8. GAP-008. Dynamic array `push`/`pop`. IF a function body contains `array.push(x)` or `array.pop()`, THEN THE Solidity_Translator SHALL NOT model the length change or the stored value. Root cause: dynamic-array mutation is not modeled; only `.length` reads are supported.
9. GAP-009. Full multi-contract inheritance with virtual dispatch. IF inheritance introduces a virtual dispatch across contracts, THEN THE Solidity_Translator SHALL treat it unsoundly. Root cause: dispatch is not implemented beyond AST-level flattening of `baseContracts`.
10. GAP-010. Storage references to struct-through-mapping and to mappings. IF a `storage` reference is taken to a struct field via a mapping (for example `Voter storage s = voters[addr]`) or to a mapping itself, THEN THE Solidity_Translator SHALL NOT produce a sound translation. Root cause: same HeapParameterization issue as GAP-002 for struct references; mapping storage references are not implemented.
11. GAP-011. XFAIL tests. THE Golden_Harness XFAIL registry SHALL currently list `test_interface_abstract` and `test_new_expression`. Root cause: specific unresolved pipeline behaviors on these inputs; details live with each test's diff in `expected/`.
12. GAP-012. Only z3 wired into the CLI. THE StrataSolidity_Binary SHALL hardcode `VerifyOptions.solver := "z3"` and SHALL NOT expose a CLI flag to select cvc5, despite the user guide and README stating that z3 and cvc5 are supported. Root cause: no flag wired through `Main.lean`.

---

### Requirement 13 — Correctness Properties to Preserve (REQ-PBT-*)

**User Story:** As the author of characterization tests for `strata-solidity-next`, I want today's invariants listed as correctness properties, so that refactors and new features do not silently change observable behavior.

These are not implementation tasks; they are behavioral invariants to pin down during design of `strata-solidity-next`.

#### Acceptance Criteria

1. REQ-PBT-001. Spec parser round-trip idempotence. WHEN a `@custom:strata` annotation is parsed, serialized back to its canonical form, and parsed again, THE Spec_Parser SHALL produce an AST equal to the first parse.
2. REQ-PBT-002. Pipeline determinism. WHEN the same `.sol` file is compiled twice with the same tool versions and the same environment, THE Verification_Pipeline SHALL produce byte-identical Laurel output, byte-identical Core output, and identical VC labels and outcomes.
3. REQ-PBT-003. Golden-test stability. WHEN any non-XFAIL `tests/test_*.sol` is run through the Golden_Harness, THE normalized output SHALL equal the committed `expected/<base>.expected`.
4. REQ-PBT-004. SARIF 2.1.0 schema compliance. WHEN `--sarif` is active, THE StrataSolidity_Binary stdout SHALL validate against the SARIF 2.1.0 JSON schema.
5. REQ-PBT-005. `--json` shape. WHEN `--json` is active, THE StrataSolidity_Binary stdout SHALL be a JSON array in which every element is an object with `name : string`, `status ∈ {"pass","fail","unknown","implementation_error"}`, and optional numeric `line` and `col`.
6. REQ-PBT-006. `--pipeline-json` shape. WHEN `--pipeline-json` is active, THE StrataSolidity_Binary stdout SHALL be a JSON object with the exact top-level keys `laurel`, `core`, `obligations`, `summary`; `obligations` items SHALL have keys `label`, `status`, `smt`, `smtResult`; `summary` SHALL have integer keys `total`, `passed`, `failed`, `unknown`.
7. REQ-PBT-007. Exit-code contract. WHEN any VC result is `fail` or `implementation_error`, THE StrataSolidity_Binary SHALL exit with code 1; otherwise it SHALL exit with code 0.
8. REQ-PBT-008. Benchmark CSV schema. THE first line of `bench/results.csv` SHALL be the literal `benchmark,functions,specs,state_vars,mappings,status,time_ms,pass,fail,unknown,total` and every data row SHALL contain exactly 11 fields in that order, with `status ∈ {ok, error, timeout}`.

---

### Requirement 14 — Non-Goals

**User Story:** As a reviewer, I want explicit non-goals listed, so that the scope boundary of `strata-solidity-next` is unambiguous.

#### Acceptance Criteria

1. THE Baseline SHALL NOT cover modifications to `solc`.
2. THE Baseline SHALL NOT cover gas modeling or cost analysis.
3. THE Baseline SHALL NOT cover Ethereum state-history or chain replay.
4. THE Baseline SHALL NOT cover cross-transaction reasoning; transient storage is modeled within a single transaction only.
5. THE Baseline SHALL NOT cover runtime enforcement of specifications; zero runtime overhead is by design.
6. THE Baseline SHALL NOT specify new annotations or new Solidity subset features; those belong to `strata-solidity-next`.

---

## Cross-reference map (quick index)

- CLI binary behavior: REQ-CLI-001..REQ-CLI-062
- Shell wrapper behavior: REQ-SH-001..REQ-SH-010
- Python tooling: REQ-PY-001..REQ-PY-032
- Output format shapes: REQ-OUT-010..REQ-OUT-045
- Solidity subset: REQ-SOL-001..REQ-SOL-100
- Specification language: REQ-SPEC-001..REQ-SPEC-070
- Pipeline: REQ-PIPE-001..REQ-PIPE-009
- Strata framework contract: REQ-STRATA-001..REQ-STRATA-005
- Distribution: REQ-DIST-001..REQ-DIST-008
- Test harnesses: REQ-TEST-001..REQ-TEST-036
- Tracked gaps: GAP-001..GAP-012
- Correctness properties (PBTs): REQ-PBT-001..REQ-PBT-008
