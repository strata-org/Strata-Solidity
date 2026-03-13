# Changelog

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
