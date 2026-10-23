# Current Limitations

StrataSolidity is under active development. This page documents known limitations.

## `unknown` results (GAP-001)

A refuted obligation is reported as `fail` (❌) with a counterexample such as `amount = 5, balance = 3` whenever z3 produces a model. With z3's model-based quantifier instantiation (MBQI) off, an obligation whose verification condition contains a universally quantified assumption is reported as `unknown` (❓) instead. The remaining sources are `sum(m)` specs (quantified update axiom), constructors that zero-initialize a mapping (Core's quantified `mapConst` axiom), `forall` specs and key-scoped `modifies` frames, nonlinear arithmetic, and solver timeouts. Each function is verified in its own SMT context, so these only affect the functions that need them.

## Struct fields through mappings (GAP-002)

Specifications cannot reference struct fields accessed through mapping values:

```solidity
struct Payment { uint256 amount; bool captured; }
mapping(bytes32 => Payment) public payments;

/// @custom:strata ensures payments[id].amount == amt  // ❌ NOT SUPPORTED
```

**Workaround:** Flatten structs into separate mappings:

```solidity
mapping(bytes32 => uint256) public paymentAmounts;
mapping(bytes32 => bool) public paymentCaptured;

/// @custom:strata ensures paymentAmounts[id] == amt  // ✅ SUPPORTED
```

## Supported patterns

| Pattern | Status |
|---|---|
| Simple mapping (`balances[msg.sender]`) | ✅ |
| Nested mapping (`allowance[from][spender]`) | ✅ |
| Nested mapping with `old()` | ✅ |
| Scalar state vars (`uint256 totalSupply`) | ✅ |
| `old()` on scalars and mappings | ✅ |
| `forall` with `==>` | ✅ |
| Key-scoped `modifies` | ✅ |
| Frame conditions (scalar and mapping key) | ✅ |
| `keccak256(...)` as mapping keys | ✅ |
| `msg.sender`, `msg.value` | ✅ |
| `type(uint256).max/min` | ✅ |
| Contract invariants | ✅ |
| Loop invariants | ✅ |
| Inherited state, functions, modifiers and invariants; virtual dispatch | ✅ |
| Base constructors, with their modifiers and arguments | ✅ |
| `super` and `Base.f()`, along the C3 linearization | ✅ |

## Not yet supported

| Pattern | Notes |
|---|---|
| Struct fields through mappings (GAP-002) | Blocked on Strata Core heap parameterization |
| Mapping and array `storage` parameters | Rejected: such a parameter refers to the caller's storage, and a write through it would not reach the state variable passed in |
| `old()` in loop invariants (GAP-003) | `__old` marker not resolved in loop context |
| `msg.sender` in constructors (GAP-006) | Constructor handling incomplete |
| External calls / reentrancy (GAP-007) | Not interpreted: a call that may re-enter the contract leaves its state unknown, except for the contract invariants (see [Contract Invariants](./contract_invariants.md#external-calls-and-reentrancy)); `--assume-no-reentrancy` trusts that calls do not re-enter |
| Assembly / inline Yul | Not interpreted: what a block may write (the variables it assigns, memory variables, contract state) is unknown afterwards, and a block that may `return` or `stop` ends the transaction on some paths, as `selfdestruct` does. A call of a function that may end the transaction is rejected |
| Dynamic arrays (`push`/`pop`) (GAP-008) | `.length` works, `push`/`pop` not modeled |
| A base contract in another file (GAP-009) | Only the contracts of the verified file are flattened into their derived contracts: an imported base's state, functions and invariants are reported as not part of the verification |
| Arguments in an inheritance specifier (`is Base(7)`) | Not read: the base constructor runs with unknown arguments of their types. Arguments given in a constructor (`constructor() Base(7)`) are used |
| A base's private state variable declared again in a derived contract | Rejected: they are different variables |
| `super.f()` of an overloaded function | Rejected |
| Lemmas (`@custom:strata lemma`) (GAP-004) | Needs Laurel grammar extension |
