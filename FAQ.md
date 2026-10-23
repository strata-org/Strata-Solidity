# Strata Solidity — Internal FAQ

## How does Strata Solidity compare to JVerify and Verus?

All three add deductive verification to existing languages. The differences come from the target language constraints.

**Spec language:**

- **Strata Solidity** — NatSpec comments (`/// @custom:strata ensures ...`). We avoid modifying solc due to its GPL-3.0 license, so structured comments are our spec mechanism.
- **JVerify** — Java library calls (`precondition(x > 0)`). Specs are valid Java that compiles and runs as no-ops. Possible because javac has a plugin API.
- **Verus** — Rust macros (`ensures(result > 0)`). Specs are part of the type system via a custom rustc fork.

All three have zero runtime overhead — specs are erased before deployment/execution.

**Translation pipeline:**

- **Strata Solidity** — solc (standard-JSON AST only) → Lean (`SolcAstParser`, `SolTranslator`), in one binary → Laurel → Core → SMT (z3)
- **JVerify** — javac plugin → Java simplification passes → Laurel (Java) → Ion → Core → SMT
- **Verus** — Custom rustc fork → VIR → SMT (no Strata — standalone tool)

Strata Solidity and JVerify share everything from Laurel onward. Improvements to HeapParameterization, Core VCG, or the SMT encoder benefit both front-ends.

## Why NatSpec comments instead of a library like JVerify?

Solidity's compiler (solc) does have a plugin system, but solc is licensed under GPL-3.0. Building a compiler plugin would create a derivative work with GPL obligations. Using NatSpec comments avoids any compiler modification — we use solc only to produce the AST, and all spec parsing happens in our own pipeline.

NatSpec is also the standard mechanism for structured metadata in Solidity — it's already used by Etherscan, documentation generators, and static analysis tools. Using `@custom:strata` (NatSpec's tag for tool-specific annotations) follows this established convention.

The tradeoff: JVerify specs are type-checked by javac (you get IDE autocomplete and compile errors on malformed specs). Strata Solidity specs are parsed by our own spec parser, so spec syntax errors only surface at verification time.

## What does Solidity make easier compared to Java or Rust?

- **No heap aliasing** — Solidity storage is a flat key-value store. Two state variables cannot point to the same memory. This eliminates the hardest part of heap reasoning that JVerify must handle.
- **No concurrency** — The EVM is single-threaded. No concurrent reasoning needed.
- **Static dispatch** — external calls are explicit, and the contract a function runs in is known: a virtual function's override and the target of `super` follow from the linearization of the contract being verified, with no run-time types to model.
- **Deterministic execution** — Same inputs always produce same outputs (modulo `block.timestamp`).
- **Simpler language** — No generics, no lambdas, no closures. The translation from Solidity to Laurel is six Lean files (about 5,200 lines, in `StrataSolidity/SolTranslator/`) vs JVerify's ~30 files.

## What does Solidity make harder?

- **No compiler plugin system** — Specs must live in comments, not in the language itself.
- **Mapping semantics** — Solidity mappings have infinite domain with default zero values. Every key "exists." This requires uninterpreted maps with select/update axioms in SMT, which is more complex than Java's finite collections.
- **EVM-specific constructs** — `msg.sender`, `msg.value`, `block.timestamp`, `payable`, reentrancy guards have no analogs in Java or Rust. Each needs explicit modeling in the translation.
- **Struct fields through mappings** — `mapping(bytes32 => Struct)` with `.field` access is a common Solidity pattern that doesn't exist in Java (Java would use `Map<K, Object>` with method calls, not field access on map values). This pattern currently hits a limitation in Strata Core's HeapParameterization.

## How much of the Strata pipeline do we share with JVerify?

Everything from Laurel onward:

```
JVerify:         Java → javac plugin → Laurel (Java) → Ion ─┐
                                                            ├→ Laurel → Core → VCG → SMT
Strata Solidity: Sol → solc JSON AST → Lean translator ─────┘
```

Strata Solidity builds its Laurel program in the same process (no Ion
serialization), and runs z3.

Shared components: Laurel AST, HeapParameterization, the Laurel-to-Core schema pass, ModifiesClauses, Core VCG, SMT encoder, solver interface. A bug fix or optimization in any of these benefits both front-ends.

## Which Strata dialect do we target and why?

Laurel. It is designed for imperative, object-oriented languages with heap-allocated objects and fields — which matches Solidity's storage model (contract = object, state variables = fields, mappings = heap-allocated maps). Laurel handles the heap parameterization automatically, converting field reads/writes into explicit heap threading that Core can verify.

The alternatives: Core is too low-level (no built-in heap model), C_Simp is a toy dialect, SMTLib is the output format. See `Strata/docs/Architecture.md` for the full dialect landscape.

## How does our architecture compare to JVerify's?

| Aspect | Strata Solidity | JVerify |
|---|---|---|
| Source compiler | solc (external, AST only) | javac (in-process plugin) |
| Spec parsing | Custom parser in Lean | javac parses specs as Java expressions |
| AST extraction | solc's JSON AST, parsed in Lean (`SolcAstParser`) | Java compiler internals → Java AST |
| Translation language | Lean 4 | Java |
| Translation to Laurel | Six Lean files (`StrataSolidity/SolTranslator/`) | ~30 Java files with simplification passes |
| Simplification passes | Minimal (Solidity is simpler) | Extensive (lambdas, generics, erasure, etc.) |
| Strata invocation | Compiled into the binary | `lake exe strata laurelAnalyzeBinary` subprocess |
| IDE integration | VS Code extension (standalone) | Any Java IDE (specs are valid Java) |

## What is the current state of the project?

See `LIMITATIONS.md` for the full supported/unsupported matrix, generated
from the capability ledger (`docs/capabilities.toml`). In summary:

<!-- capabilities:begin highlights -->
<!-- Generated from docs/capabilities.toml by scripts/capabilities.py: edit the ledger, then run the script. -->
**Works today:**

- Simple and nested mappings, with `old()`
- Contract invariants, including `sum(mapping)`, checked across external calls that may re-enter the contract
- Key-scoped `modifies` frame conditions
- `forall` quantifiers, with `==>`
- Loop invariants, with `old()`
- Inheritance: inherited state, functions, modifiers, invariants and constructors, and `super`
- Integer conversions, wrapping and signed division as the EVM performs them
- Plain-text, JSON and SARIF output, with counterexamples when z3 produces a model

**Not yet:**

- Struct-valued mappings and arrays of structs (functions using them are not verified)
- Library calls and `using … for`
- `revert("reason")` (`require` and custom errors work)
- Strings and dynamic `bytes` values
- Array `pop()`
- Constructors that call internal functions using state (the `_mint` pattern)
- A base contract imported from another file
- Conclusive results for every property over `sum`, `forall` and key-scoped frames: some are ❓ unknown
<!-- capabilities:end highlights -->

## Why does Solidity need fewer simplification passes than Java?

JVerify runs ~10 simplification passes on the Java AST before translating to Laurel: lambda-to-anonymous-class conversion, generic type erasure, method reference desugaring, array covariance handling, etc. Strata Solidity has none of these.

Solidity doesn't have lambdas, generics, method references, anonymous classes, covariant arrays, checked exceptions, or autoboxing. The language that reaches the translator is essentially what the developer wrote — there's very little to desugar. The spec parser and frame condition generator are the most complex parts of our front-end, not the body translation.

This is why the translation is six Lean files (about 5,200 lines) while JVerify's translation layer is ~30 Java files. It's not that our code is more compact — Solidity genuinely has fewer constructs to handle.

## Why doesn't Solidity need the heap aliasing reasoning that Java does?

In Java, two variables can reference the same object: `List<Integer> a = b;` means `a` and `b` alias the same heap location. Modifying `a` modifies `b`. JVerify must reason about this — every method call could potentially modify any object reachable through any alias. This is the core difficulty of heap verification in object-oriented languages.

Solidity state variables never alias. Each state variable occupies a distinct storage slot. `mapping(address => uint256) balances` and `uint256 totalSupply` can never point to the same memory, and the only way to modify `balances` is to write to `balances` (or to a `storage` reference to it). Aliasing exists only through `storage` references (`Info storage d = data;`) and between memory values (assigning a memory struct or array to another shares it), which the translator handles case by case: see `LIMITATIONS.md`.

This means our heap model is simpler: each mapping is an independent `Map[int, int]` parameter, and scalar state vars are fields of a single `self` composite. We don't need alias analysis, separation logic, or ownership tracking. The frame condition "only `balances` changed" is a direct equality check on the other variables, not a complex reachability argument.

## Where is the code hosted?

In the `strata-org` organization, at <https://github.com/strata-org/Strata-Solidity>, next to [Strata](https://github.com/strata-org/Strata) itself, which it vendors as a git submodule.
