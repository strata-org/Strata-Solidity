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

## Not yet supported

| Pattern | Notes |
|---|---|
| Struct fields through mappings (GAP-002) | Blocked on Strata Core heap parameterization |
| `old()` in loop invariants (GAP-003) | `__old` marker not resolved in loop context |
| `block.timestamp` (GAP-005) | No time abstraction yet |
| `msg.sender` in constructors (GAP-006) | Constructor handling incomplete |
| External calls / reentrancy (GAP-007) | No cross-contract reasoning |
| Assembly / inline Yul | Not interpreted: what a block may write (the variables it assigns, memory variables, contract state) is unknown afterwards, and a block that may `return` or `stop` ends the function on some paths |
| Dynamic arrays (`push`/`pop`) (GAP-008) | `.length` works, `push`/`pop` not modeled |
| Inheritance (GAP-009) | Single contract only, no virtual dispatch |
| Lemmas (`@custom:strata lemma`) (GAP-004) | Needs Laurel grammar extension |
