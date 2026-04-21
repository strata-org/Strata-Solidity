# Strata Solidity — Internal FAQ

## How does Strata Solidity compare to JVerify and Verus?

All three add deductive verification to existing languages. The differences come from the target language constraints.

**Spec language:**

- **Strata Solidity** — NatSpec comments (`/// @custom:strata ensures ...`). Solidity's compiler has no plugin system, so structured comments are the only extension point.
- **JVerify** — Java library calls (`precondition(x > 0)`). Specs are valid Java that compiles and runs as no-ops. Possible because javac has a plugin API.
- **Verus** — Rust macros (`ensures(result > 0)`). Specs are part of the type system via a custom rustc fork.

All three have zero runtime overhead — specs are erased before deployment/execution.

**Translation pipeline:**

- **Strata Solidity** — solc (AST only) → Python (solast.py) → Ion → Lean (SolToLaurel) → Laurel → Core → SMT
- **JVerify** — javac plugin → Java simplification passes → Laurel (Java) → Ion → Core → SMT
- **Verus** — Custom rustc fork → VIR → SMT (no Strata — standalone tool)

Strata Solidity and JVerify share everything from Laurel onward. Improvements to HeapParameterization, Core VCG, or the SMT encoder benefit both front-ends.

## Why NatSpec comments instead of a library like JVerify?

Solidity's compiler (solc) has no plugin system. There is no way to hook into solc's compilation pipeline the way JVerify hooks into javac. NatSpec is the standard mechanism for structured metadata in Solidity — it's already used by tools like Etherscan, NatSpec doc generators, and Slither. Using `@custom:strata` follows this convention.

The tradeoff: JVerify specs are type-checked by javac (you get IDE autocomplete and compile errors on malformed specs). Strata Solidity specs are parsed by our own spec parser, so spec syntax errors only surface at verification time.

## What does Solidity make easier compared to Java or Rust?

- **No heap aliasing** — Solidity storage is a flat key-value store. Two state variables cannot point to the same memory. This eliminates the hardest part of heap reasoning that JVerify must handle.
- **No concurrency** — The EVM is single-threaded. No concurrent reasoning needed.
- **No dynamic dispatch** — Solidity has inheritance but external calls are explicit. No virtual method resolution to model.
- **Deterministic execution** — Same inputs always produce same outputs (modulo `block.timestamp`).
- **Simpler language** — No generics, no lambdas, no closures. The translation from Solidity to Laurel is a single file (~2100 lines) vs JVerify's ~30 files.

## What does Solidity make harder?

- **No compiler plugin system** — Specs must live in comments, not in the language itself.
- **Mapping semantics** — Solidity mappings have infinite domain with default zero values. Every key "exists." This requires uninterpreted maps with select/update axioms in SMT, which is more complex than Java's finite collections.
- **EVM-specific constructs** — `msg.sender`, `msg.value`, `block.timestamp`, `payable`, reentrancy guards have no analogs in Java or Rust. Each needs explicit modeling in the translation.
- **Struct fields through mappings** — `mapping(bytes32 => Struct)` with `.field` access is a common Solidity pattern that doesn't exist in Java (Java would use `Map<K, Object>` with method calls, not field access on map values). This pattern currently hits a limitation in Strata Core's HeapParameterization.

## How much of the Strata pipeline do we share with JVerify?

Everything from Laurel onward:

```
JVerify:         Java → javac plugin → Laurel (Java) ─┐
                                                       ├→ Ion → Laurel → Core → VCG → SMT → z3/cvc5
Strata Solidity: Sol → solc → solast.py → Lean ────────┘
```

Shared components: Laurel AST, HeapParameterization, LaurelToCoreTranslator, ModifiesClauses, Core VCG, SMT encoder, solver interface. A bug fix or optimization in any of these benefits both front-ends.

## Which Strata dialect do we target and why?

Laurel. It is designed for imperative, object-oriented languages with heap-allocated objects and fields — which matches Solidity's storage model (contract = object, state variables = fields, mappings = heap-allocated maps). Laurel handles the heap parameterization automatically, converting field reads/writes into explicit heap threading that Core can verify.

The alternatives: Core is too low-level (no built-in heap model), C_Simp is a toy dialect, SMTLib is the output format. See `Strata/docs/Architecture.md` for the full dialect landscape.

## How does our architecture compare to JVerify's?

| Aspect | Strata Solidity | JVerify |
|---|---|---|
| Source compiler | solc (external, AST only) | javac (in-process plugin) |
| Spec parsing | Custom parser in Lean | javac parses specs as Java expressions |
| AST extraction | Python (solast.py) → Ion | Java compiler internals → Java AST |
| Translation language | Lean 4 | Java |
| Translation to Laurel | Single file (SolToLaurel.lean) | ~30 Java files with simplification passes |
| Simplification passes | Minimal (Solidity is simpler) | Extensive (lambdas, generics, erasure, etc.) |
| Strata invocation | Compiled into the binary | `lake exe strata laurelAnalyzeBinary` subprocess |
| IDE integration | VS Code extension (standalone) | Any Java IDE (specs are valid Java) |

## What is the current state of the project?

See `LIMITATIONS.md` for the full supported/unsupported matrix. In summary:

**Working:** Simple and nested mappings, scalar state vars, `old()`, `forall` with `==>`, key-scoped `modifies`, `sum()` aggregation, contract invariants, loop invariants, `keccak256(...)` as mapping keys.

**Not working:** Struct fields through mappings (Core limitation), counterexample generation (z3 mbqi disabled), external calls/reentrancy, inheritance, assembly.

## Where is the code hosted?

Currently independent (option 3 per Strata's `frontend_hosting.md`). Target: `strata-org` organization (option 2) once we meet the quality bar — test suite, source location propagation, codebase restructuring. See the "Front-end conformity" task in Asana for the gap analysis.
