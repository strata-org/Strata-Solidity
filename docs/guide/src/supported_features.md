# Supported Solidity Features

StrataSolidity supports a substantial subset of Solidity. Support is being expanded incrementally.

## Currently supported

**Core constructs:**
- Contracts, functions (public/external/internal/private), state variables, constructors
- Inheritance (single and diamond)
- Modifiers, inlined with their arguments (`_` stands for the rest of the function; not modifiers of an imported base contract)

**Types:**
- `uint`/`int` (all sizes 8–256), `bool`, `address`, `bytes32`
- Mappings (simple and nested)
- Arrays (fixed and dynamic)
- Structs, enums, user-defined value types

**Statements:**
- `if`/`else`, `while`, `for`, `return`
- `require`, `assert`, `revert`
- `unchecked` blocks, `delete`

**Expressions:**
- Arithmetic: `+`, `-`, `*`, `/`, `%`, `**`
- Comparison: `==`, `!=`, `>=`, `<=`, `>`, `<`
- Boolean logic: `&&`, `||`, `!`
- Bitwise: `&`, `|`, `^`, `~`, `<<`, `>>`
- Ternary: `? :`
- Index access, member access, type casts

**Additional:**
- Events (`emit`) — treated as no-ops for verification
- `receive`/`fallback` functions
- `immutable` and `constant` variables
- Hash functions (`keccak256`, `sha256`) and `abi.encode*` — modeled as uninterpreted functions
- Inline assembly — havoc strategy (what a block may write is unknown afterwards)
- Custom errors with `revert`
- `msg.sender`, `msg.value`, `block.*`, `tx.*` globals
- `type(uint256).max`, `type(uint256).min` compile-time constants

## Specification features

| Feature | Status |
|---|---|
| `requires` / `ensures` | ✅ |
| `invariant` (contract-level) | ✅ |
| `modifies` (field and key-scoped) | ✅ |
| `loop-invariant` | ✅ |
| `forall` / `exists` quantifiers | ✅ |
| `old()` on scalars and mappings | ✅ |
| `==>` (implication) in specs | ✅ |
| `keccak256(...)` as mapping keys | ✅ |

## Not yet supported

See [Current Limitations](./limitations.md) for the full list. Major gaps:

- Struct fields accessed through mapping values
- `old()` in loop invariants
- External calls / cross-contract reasoning
- Counterexample generation
- `msg.sender` in constructors

If you encounter something not in either list, please open a GitHub issue.
