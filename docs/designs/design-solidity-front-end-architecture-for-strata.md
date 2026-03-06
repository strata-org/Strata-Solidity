# Design: Solidity Front-End Architecture for Strata

## 1. Problem Statement

Strata currently supports verification of Python programs through a pipeline
that translates Python AST → Laurel IR → Strata Core → VCG → SMT. We need
an analogous pipeline for Solidity smart contracts.

Solidity is the dominant language for Ethereum smart contracts. Bugs in smart
contracts are high-impact — they can lead to irreversible loss of funds. Formal
verification is therefore especially valuable for Solidity.

The front-end must handle Solidity's distinctive features:

**Value types and fixed-precision arithmetic:**
```solidity
function safeAdd(uint256 a, uint256 b) public pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a, "overflow");
    return c;
}
```
Solidity `uint256` is a 256-bit unsigned integer. Arithmetic wraps by default
in Solidity ≥0.8 (with automatic overflow checks), and the verifier must
model this precisely.

**Contracts with state and require-based assertions:**
```solidity
contract Token {
    mapping(address => uint256) public balances;

    function transfer(address to, uint256 amount) public {
        require(balances[msg.sender] >= amount, "insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        assert(balances[msg.sender] + balances[to] >= amount);
    }
}
```
Contracts have persistent state (storage variables), and `require`/`assert`
are the natural specification mechanism. `msg.sender` and other transaction
context variables must be modeled.

**Pure/view functions as the initial target:**
```solidity
function max(uint256 a, uint256 b) public pure returns (uint256) {
    if (a >= b) {
        return a;
    } else {
        return b;
    }
    // Verification target:
    assert(max(a, b) >= a && max(a, b) >= b);
}
```

The goal is to verify `assert()` statements in Solidity code by translating
them through the existing Laurel → Core → SMT pipeline.

## 2. Background

### 2.1 The Python Front-End Pipeline (Reference Model)

The Python front-end is the closest existing analogue and serves as the
reference architecture. Its pipeline is:

```
Python (.py)
  → [Tools/Python/strata/gen.py: py_to_strata]  (external Python process)
  → .python.st.ion                                (Ion binary AST)
  → [Strata/Languages/Python/ReadPython.lean]     (read Ion into Lean)
  → Python AST (Lean types from DDM)
  → [Strata/Languages/Python/PythonToLaurel.lean] (translate to Laurel)
  → Laurel.Program
  → [Strata/Languages/Laurel/LaurelToCoreTranslator.lean: translate]
  → Core.Program
  → [Strata/Languages/Core/Verifier.lean: verify]
  → VCResults
```

Key implementation files:

| Component | File | Role |
|-----------|------|------|
| External parser | `Tools/Python/strata/pythonast.py` | Generates DDM dialect from Python `ast` module, parses `.py` to Ion |
| Ion reader | `Strata/Languages/Python/ReadPython.lean` | Reads Ion bytes, converts DDM AST to typed Lean structures |
| AST→Laurel | `Strata/Languages/Python/PythonToLaurel.lean` | `TranslationContext` + recursive translation of statements/expressions |
| Laurel→Core | `Strata/Languages/Laurel/LaurelToCoreTranslator.lean` | `translate : Program → Except ... (Core.Program × ...)` |
| CLI entry | `StrataMain.lean` | `pyAnalyzeLaurel` command orchestrates the full pipeline |

The external parser (`gen.py`) uses Python's built-in `ast` module to parse
source code, then serializes the AST to Ion binary format using the DDM
(Dialect Definition Mechanism). The Lean side reads the Ion file and
reconstructs typed AST nodes.

### 2.2 The DDM and Ion Format

Strata uses the DDM to define language ASTs declaratively. A dialect definition
specifies operations (AST node types) with typed arguments. The `strata.base`
Python module (`Tools/Python/strata/base.py`) provides the core infrastructure
for serializing ASTs to Ion binary format.

The Python front-end generates its dialect definition programmatically from
Python's `ast` module (`pythonast.py: gen_dialect()`). The dialect file
(`.dialect.st.ion`) is then used by both the parser (to serialize) and the
Lean reader (to deserialize).

### 2.3 The Laurel IR

Laurel (`Strata/Languages/Laurel/Laurel.lean`) is a common intermediate
representation for imperative languages. Key types:

- `Program` — top-level: `staticProcedures`, `staticFields`, `types`, `constants`
- `Procedure` — name, inputs, outputs, preconditions, body (Transparent/Opaque/Abstract/External)
- `StmtExpr` — unified statement/expression type: `IfThenElse`, `Block`, `LocalVariable`, `While`, `Return`, `LiteralInt`, `Identifier`, `Assign`, `StaticCall`, `BinaryOp`, etc.
- `HighType` — `TBool`, `TInt`, `TFloat64`, `TString`, `UserDefined`, `TMap`, `TSet`, etc.
- `CompositeType` — class-like types with fields and instance procedures

The Laurel→Core translator (`LaurelToCoreTranslator.lean`) performs several
passes: resolution, heap parameterization, type hierarchy transform, modifies
clause inference, and expression lifting before generating Core procedures.

### 2.4 Solidity-Specific Considerations

Solidity differs from Python in ways that affect the translation:

1. **Fixed-width integers**: `uint256`, `int128`, etc. — not arbitrary-precision.
   Core supports bitvectors (`bv<n>`), which map directly.
2. **Mappings**: `mapping(K => V)` — infinite-domain maps. Core has `Map a b`.
3. **Contract state**: Storage variables persist across function calls. This
   maps to Laurel's `staticFields` + heap parameterization.
4. **`require`/`assert`**: `require(cond)` reverts on failure (precondition);
   `assert(cond)` checks an invariant (verification target).
5. **`msg.sender`, `msg.value`**: Transaction context — modeled as procedure
   inputs or global constants.
6. **No dynamic dispatch in scope**: Solidity function calls within a contract
   are statically resolved (ignoring `delegatecall`).

## 3. Design Options

### Option A: External Parser Using `solc --ast-json`

Use the Solidity compiler's built-in JSON AST output as the parsing front-end.

#### a. Implementation Strategy

```
Solidity (.sol)
  → [solc --ast-json]                              (external process)
  → AST JSON
  → [Tools/Solidity/src/solast.py: sol_to_strata]  (Python: JSON → Ion)
  → .solidity.st.ion
  → [Strata/Languages/Solidity/ReadSolidity.lean]  (Ion → Lean AST)
  → Solidity AST
  → [Strata/Languages/Solidity/SolToLaurel.lean]   (→ Laurel)
  → Laurel.Program
  → existing Laurel → Core → SMT pipeline
```

New files:

| File | Purpose |
|------|---------|
| `Tools/Solidity/src/solast.py` | Define Solidity DDM dialect, convert `solc` JSON AST to Ion |
| `Tools/Solidity/src/base_dialect.py` | Solidity dialect definition (operations for each AST node) |
| `Strata/Languages/Solidity/SolidityDialect.lean` | DDM dialect registration in Lean |
| `Strata/Languages/Solidity/ReadSolidity.lean` | Read Ion, produce typed Lean AST |
| `Strata/Languages/Solidity/SolToLaurel.lean` | Translate Solidity AST → Laurel Program |
| `StrataMain.lean` | Add `solAnalyze` command |
| `StrataTest/Languages/Solidity/tests/*.sol` | Test Solidity source files |
| `StrataTest/Languages/Solidity/run_sol_analyze.sh` | Test runner script |

The Python script `solast.py` would:
1. Invoke `solc --ast-json <file.sol>` to get the compiler's AST
2. Parse the JSON output
3. Map each JSON AST node to a DDM operation
4. Serialize to Ion binary format

#### b. Internal Representation

The Solidity AST in Lean would mirror `solc`'s AST node types. Key mappings
to Laurel:

| Solidity Construct | Laurel Representation |
|---|---|
| `contract C { ... }` | `CompositeType` with fields + instance procedures |
| `uint256 x` | `HighType.TInt` (Phase 1) or bitvector type (Phase 2) |
| `mapping(K => V)` | `HighType.TMap K V` |
| `function f(x) returns (y) { ... }` | `Procedure` with inputs/outputs |
| `require(cond, msg)` | `StmtExpr.StaticCall "assume" [cond]` (precondition) |
| `assert(cond)` | `StmtExpr.StaticCall "assert" [cond]` (verification target) |
| `msg.sender` | Procedure input parameter of type `TInt` (address as integer) |
| `if/else` | `StmtExpr.IfThenElse` |
| `while` | `StmtExpr.While` |
| `x = expr` | `StmtExpr.Assign` |
| `a + b` (uint256) | `StmtExpr.BinaryOp .Add` |
| `m[k]` (mapping read) | `StmtExpr.MapRead` or `StmtExpr.StaticCall "map_select"` |
| `m[k] = v` (mapping write) | `StmtExpr.Assign` with `StmtExpr.StaticCall "map_store"` |

#### c. End-to-End Correctness

The `solc` compiler is the authoritative Solidity parser. Using its AST output
guarantees parsing correctness — we get exactly the AST that the compiler
would compile. The risk shifts entirely to the AST→Laurel translation.

For the translation to be correct end-to-end:

1. **Type mapping**: `uint256` must be modeled with the right semantics.
   Phase 1 uses `TInt` (unbounded) with explicit overflow checks via
   `require(x >= 0 && x < 2^256)`. Phase 2 uses `bv<256>` for precise
   bitvector semantics.

2. **`require` vs `assert`**: `require` becomes `assume` (restricts the
   state space); `assert` becomes a verification obligation. Getting this
   wrong would be unsound.

3. **Storage model**: Contract state variables become Laurel `staticFields`.
   The heap parameterization pass in `LaurelToCoreTranslator.lean` already
   handles mutable fields — this is the same mechanism used for Python objects.

4. **Mapping semantics**: Solidity mappings have default-zero semantics
   (`m[k]` returns 0 for uninitialized keys). This must be encoded as an
   axiom or initial condition in the Core program.

#### d. Testing Strategy

Follow the Python test pattern:

```
StrataTest/Languages/Solidity/
  tests/
    test_arithmetic.sol          # uint256 arithmetic + assert
    test_require.sol             # require as precondition
    test_mapping.sol             # mapping read/write
    test_control_flow.sol        # if/else, while
    test_pure_function.sol       # pure function verification
  expected/
    test_arithmetic.expected     # expected verification output
    ...
  run_sol_analyze.sh             # test runner
```

Each `.sol` file contains a contract with `assert()` statements. The test
runner invokes the full pipeline and diffs against expected output.

Limitations:
- Requires `solc` to be installed (external dependency)
- `solc` version changes may alter the JSON AST format
- Cannot verify Solidity syntax that `solc` rejects (e.g., partial programs)

#### e. Complexity and Risk

| Aspect | Assessment |
|--------|------------|
| New files | ~6 Lean files, ~2 Python files, test infrastructure |
| External dependency | `solc` compiler (well-maintained, stable AST format) |
| Parsing risk | None — delegated to `solc` |
| Translation risk | Medium — AST→Laurel mapping is the main work |
| Maintenance risk | Low-medium — `solc` AST format is versioned and stable |
| Breakage risk | Low — no changes to existing Strata code |

---

### Option B: Custom Parser in Python (Like the Python Front-End)

Write a custom Solidity parser in Python that directly produces Ion output,
analogous to `pythonast.py`.

#### a. Implementation Strategy

```
Solidity (.sol)
  → [Tools/Solidity/src/solparser.py]  (custom Python parser → Ion)
  → .solidity.st.ion
  → [Strata/Languages/Solidity/ReadSolidity.lean]
  → Solidity AST
  → [Strata/Languages/Solidity/SolToLaurel.lean]
  → Laurel.Program
  → existing pipeline
```

The custom parser would use a Python parsing library (e.g., `lark`, `ply`, or
hand-written recursive descent) to parse Solidity source into an AST, then
serialize to Ion.

New files are the same as Option A, except `solast.py` is replaced by
`solparser.py` (significantly larger — a full Solidity grammar implementation).

#### b. Internal Representation

Same as Option A — the Laurel mapping is identical regardless of how the AST
is produced.

#### c. End-to-End Correctness

The custom parser introduces a significant correctness risk: any deviation
from the Solidity specification means the verifier is analyzing a different
program than what the compiler would compile. Solidity's grammar has
subtleties (operator precedence, type coercion rules, implicit conversions)
that are easy to get wrong.

This risk does not exist in Option A because `solc` is the reference
implementation.

#### d. Testing Strategy

Same test structure as Option A, but additionally requires parser-level unit
tests to validate that the custom parser matches `solc`'s interpretation.
This is a substantial testing burden.

#### e. Complexity and Risk

| Aspect | Assessment |
|--------|------------|
| New files | ~6 Lean files, ~5+ Python files (parser + grammar), test infrastructure |
| External dependency | None (no `solc` needed) |
| Parsing risk | **High** — Solidity grammar is complex; maintaining parity with `solc` is ongoing work |
| Translation risk | Medium — same as Option A |
| Maintenance risk | **High** — must track Solidity language evolution |
| Breakage risk | Low — no changes to existing Strata code |

---

### Option C: Use `solc --ast-json` with Direct JSON-to-Laurel in Lean (No Ion)

Skip the Ion intermediate format entirely. Parse `solc`'s JSON AST directly
in Lean and translate to Laurel in one step.

#### a. Implementation Strategy

```
Solidity (.sol)
  → [solc --ast-json]                                    (external process)
  → AST JSON (String)
  → [Strata/Languages/Solidity/SolJsonToLaurel.lean]     (JSON → Laurel directly)
  → Laurel.Program
  → existing pipeline
```

This eliminates the Python tooling layer and the Ion serialization step. The
Lean code would use `Lean.Json` to parse the JSON and directly construct
Laurel AST nodes.

New files:

| File | Purpose |
|------|---------|
| `Strata/Languages/Solidity/SolJsonToLaurel.lean` | Parse JSON AST, translate to Laurel |
| `Strata/Languages/Solidity/SolTypes.lean` | Solidity type definitions and mapping |
| `StrataMain.lean` | Add `solAnalyze` command |
| `StrataTest/Languages/Solidity/tests/*.sol` | Test files |
| `StrataTest/Languages/Solidity/run_sol_analyze.sh` | Test runner |

#### b. Internal Representation

No intermediate Solidity AST in Lean — the JSON is traversed and Laurel nodes
are constructed directly. This means there is no reusable Solidity AST type,
which limits future extensibility (e.g., Solidity-specific analyses before
translation).

#### c. End-to-End Correctness

Same parsing correctness as Option A (uses `solc`). The translation
correctness argument is slightly weaker because there is no intermediate
typed AST to inspect — errors in JSON field access are runtime failures
rather than type errors.

However, the pipeline is simpler (fewer stages = fewer places for bugs).

#### d. Testing Strategy

Same as Option A. Slightly easier to debug because there is one fewer
serialization/deserialization step.

#### e. Complexity and Risk

| Aspect | Assessment |
|--------|------------|
| New files | ~3 Lean files, test infrastructure (no Python tooling) |
| External dependency | `solc` compiler |
| Parsing risk | None — delegated to `solc` |
| Translation risk | Medium — JSON traversal is less type-safe than DDM |
| Maintenance risk | Medium — `solc` JSON format changes require Lean code changes |
| Breakage risk | Low — no changes to existing Strata code |
| Extensibility | **Lower** — no reusable Solidity AST for future analyses |

## 4. Recommendation

**Recommended: Option A — External Parser Using `solc --ast-json` with Ion serialization.**

Rationale:

1. **Parsing correctness is free.** `solc` is the reference Solidity compiler.
   Using its AST output eliminates the entire class of parsing bugs that would
   plague Option B. This is critical for a verification tool — if the parser
   disagrees with the compiler, verification results are meaningless.

2. **Follows the established pattern.** Option A mirrors the Python front-end
   architecture exactly: external parser → Ion → Lean reader → Laurel. This
   means the team already knows how to build, test, and maintain this kind of
   pipeline. The `strata.base` Python module provides reusable infrastructure
   for Ion serialization.

3. **Typed intermediate AST.** Unlike Option C, Option A produces a typed
   Solidity AST in Lean via the DDM. This enables future Solidity-specific
   analyses (e.g., reentrancy detection, storage layout analysis) before
   translation to Laurel.

4. **Manageable complexity.** The main implementation work is the
   `SolToLaurel.lean` translation, which is the same across all options.
   Option A adds modest overhead for the DDM dialect definition and Ion
   serialization, but this is well-understood infrastructure.

5. **`solc` AST stability.** The `solc` JSON AST format is versioned and
   widely used by other tools (Slither, Mythril, etc.). Breaking changes are
   rare and well-documented.

### Proposed Phased Rollout

**Phase 1 — Pure functions with value types (MVP)**

Scope: `pure` functions, `uint256`/`int256`/`bool`, `require`, `assert`,
`if/else`, `return`, arithmetic operators, comparison operators.

Modeling: `uint256` → `HighType.TInt` with explicit bounds checks
(`require(x >= 0 && x < 2^256)`). This is sound but conservative — it
rejects programs that rely on wrapping arithmetic.

Deliverables:
- `Tools/Solidity/src/solast.py` — dialect definition + `solc` JSON → Ion
- `Strata/Languages/Solidity/SolToLaurel.lean` — core translation
- `StrataMain.lean` — `solAnalyze` command
- 5+ integration tests

**Phase 2 — Contract state and mappings**

Scope: State variables, `mapping(K => V)`, `msg.sender`, `view` functions,
simple storage reads/writes.

Modeling: Contract → `CompositeType` with fields. Mappings → `TMap`.
`msg.sender` → procedure input parameter. Leverage Laurel's existing heap
parameterization for mutable state.

**Phase 3 — Bitvector precision and overflow semantics**

Scope: Replace `TInt` modeling with `bv<256>` (and other widths). Model
Solidity ≥0.8 automatic overflow checks. Support `unchecked { }` blocks.

Modeling: `uint256` → Core `bv<256>`. Arithmetic operations use bitvector
ops (`BV.Add`, `BV.ULt`, etc.). Overflow checks become explicit `assert`
statements unless inside `unchecked`.

**Phase 4 — Structs, enums, arrays, and modifiers**

Scope: User-defined structs, enums, fixed-size arrays, dynamic arrays,
function modifiers.

Modeling: Structs → `CompositeType`. Enums → integer constants. Arrays →
`TMap Nat T` with a length field. Modifiers → inlined precondition/
postcondition blocks.

**Phase 5 — Inheritance and advanced features**

Scope: Contract inheritance, interface implementation, `super` calls,
events (as no-ops for verification), `revert` with custom errors.

This phase requires Laurel's type hierarchy support
(`TypeHierarchy.lean`) for modeling inheritance.

## 5. `solc` AST Reference for Phase 1

The recommended approach (Option A) uses `solc`'s standard JSON interface.
The input requests AST output; the relevant output is in
`sources.<file>.ast`, which is a `SourceUnit` node.

### 5.1 Invoking `solc`

Use the standard JSON interface rather than `--ast-compact-json` for
stability and control:

```json
{
  "language": "Solidity",
  "sources": {
    "input.sol": { "content": "<solidity source>" }
  },
  "settings": {
    "outputSelection": {
      "*": { "": ["ast"] }
    }
  }
}
```

Invoke: `echo '<json>' | solc --standard-json`

The AST is in `output.sources["input.sol"].ast`.

### 5.2 AST Node Structure

Every node has `nodeType` (string), `id` (integer), and `src` (source
range as `"start:length:fileIndex"`). The Phase 1 node types are:

| `nodeType` | Solidity Construct | Key Fields |
|---|---|---|
| `SourceUnit` | File root | `nodes` (array of top-level nodes) |
| `PragmaDirective` | `pragma solidity ^0.8.0;` | `literals` |
| `ContractDefinition` | `contract C { ... }` | `name`, `nodes`, `contractKind` |
| `FunctionDefinition` | `function f(...) ... { ... }` | `name`, `parameters`, `returnParameters`, `body`, `stateMutability`, `visibility`, `kind` |
| `ParameterList` | `(uint256 a, bool b)` | `parameters` (array of `VariableDeclaration`) |
| `VariableDeclaration` | `uint256 x` | `name`, `typeName`, `stateVariable`, `constant` |
| `Block` | `{ ... }` | `statements` |
| `ExpressionStatement` | `x = 1;` | `expression` |
| `Return` | `return expr;` | `expression` |
| `IfStatement` | `if (...) { ... } else { ... }` | `condition`, `trueBody`, `falseBody` |
| `WhileStatement` | `while (...) { ... }` | `condition`, `body` |
| `VariableDeclarationStatement` | `uint256 x = expr;` | `declarations`, `initialValue` |
| `Assignment` | `x = expr` | `leftHandSide`, `rightHandSide`, `operator` |
| `BinaryOperation` | `a + b` | `leftExpression`, `rightExpression`, `operator` |
| `UnaryOperation` | `!x`, `-x` | `subExpression`, `operator`, `prefix` |
| `FunctionCall` | `require(cond)`, `f(x)` | `expression`, `arguments`, `kind` |
| `Identifier` | `x` | `name`, `referencedDeclaration` |
| `Literal` | `42`, `true`, `"hello"` | `value`, `kind` (`number`, `bool`, `string`) |
| `ElementaryTypeName` | `uint256`, `bool`, `address` | `name` |
| `MemberAccess` | `msg.sender` | `expression`, `memberName` |
| `IndexAccess` | `m[k]` | `baseExpression`, `indexExpression` |

### 5.3 Type Information

Each expression node includes a `typeDescriptions` object:
```json
"typeDescriptions": {
  "typeIdentifier": "t_uint256",
  "typeString": "uint256"
}
```

Phase 1 type identifiers to handle:
- `t_uint256`, `t_int256` — 256-bit integers
- `t_bool` — boolean
- `t_address` — 160-bit address (model as `uint160` or abstract integer)
- `t_mapping$_t_address_$_t_uint256_$` — mapping types (Phase 2)

### 5.4 DDM Dialect Mapping

The Python script (`solast.py`) defines a DDM dialect with one operation
per AST node type. The mapping follows the same pattern as `pythonast.py`:

```
solc nodeType    →  DDM operation name    →  DDM arguments
─────────────────────────────────────────────────────────────
SourceUnit       →  SourceUnit            →  Seq(node)
ContractDef      →  ContractDefinition    →  Str(name), Seq(node), ...
FunctionDef      →  FunctionDefinition    →  Str(name), parameters, returnParameters, body, ...
BinaryOperation  →  BinaryOperation       →  expr, expr, Str(operator)
Literal          →  Literal               →  Str(value), Str(kind)
...
```

The Lean reader (`ReadSolidity.lean`) deserializes Ion back into typed
Lean structures, and `SolToLaurel.lean` translates those to Laurel.

## 6. Open Questions and Risks

### 6.1 Open Questions

1. **`solc` version pinning**: Should we pin a specific `solc` version
   (e.g., 0.8.28) or support a range? The AST format is stable across
   0.8.x but minor field additions occur. Recommendation: pin to a
   minimum version (≥0.8.20) and test against latest.

2. **`require` vs `assert` semantics**: In Solidity, `require` reverts
   the transaction (precondition), while `assert` signals an invariant
   violation (verification target). The design maps `require` → `assume`
   and `assert` → `assert`. Should we also support `revert` statements
   as precondition failures in Phase 1, or defer to Phase 5?
   Recommendation: defer `revert` to Phase 5; Phase 1 only handles
   `require` and `assert`.

3. **Integer overflow modeling in Phase 1**: Phase 1 uses `TInt`
   (unbounded) with explicit bounds. Should bounds checks be inserted
   automatically for every arithmetic operation, or only when the user
   writes `require(x < 2**256)`? Recommendation: insert automatic
   bounds checks for all arithmetic on `uint256`/`int256` to match
   Solidity ≥0.8 semantics (which reverts on overflow).

4. **`address` type representation**: `address` is a 160-bit value.
   Phase 1 can model it as an abstract integer type. Phase 3 would
   use `bv<160>`. Is the abstract integer sufficient for Phase 1
   use cases (primarily `msg.sender` equality checks)?
   Recommendation: yes, abstract integer is sufficient for Phase 1.

### 6.2 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `solc` not installed on developer machines | Medium | Blocks all testing | Document in README; provide install script; CI ensures `solc` available |
| `solc` JSON AST format changes in future versions | Low | Breaks parser | Pin minimum version; test against multiple versions in CI |
| Laurel IR lacks constructs for Solidity features | Low | Blocks translation | Laurel already supports maps, composite types, static fields — covers Phase 1-2 |
| Bitvector support in Core is incomplete | Medium | Blocks Phase 3 | Phase 1-2 use `TInt`; Phase 3 can be deferred until Core `bv<n>` is mature |
| `mapping` default-zero semantics not expressible | Low | Incorrect verification | Encode as axiom `∀k. m[k] = 0` for fresh mappings in Phase 2 |

## 7. Summary

This design recommends **Option A** (external parser using `solc --ast-json`
with Ion serialization) for the Solidity front-end. The architecture mirrors
the existing Python pipeline, reuses the Laurel IR and Core verification
backend, and delegates parsing to the authoritative Solidity compiler.

The implementation is structured in 5 phases, starting with pure functions
and value types (Phase 1) and progressing through contract state, bitvector
precision, user-defined types, and inheritance.

Key deliverables for Phase 1:
- `Tools/Solidity/src/solast.py` — DDM dialect + `solc` JSON → Ion
- `Strata/Languages/Solidity/ReadSolidity.lean` — Ion → typed Lean AST
- `Strata/Languages/Solidity/SolToLaurel.lean` — Solidity AST → Laurel
- `StrataMain.lean` — `solAnalyzeLaurel` command
- Integration tests in `StrataTest/Languages/Solidity/`
