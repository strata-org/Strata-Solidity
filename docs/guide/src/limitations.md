# Current Limitations

StrataSolidity is under active development. This page documents known limitations.

## No counterexample generation

When a postcondition cannot be proven, the verifier reports `unknown` (❓) instead of `fail` (❌) with a concrete counterexample. You know something is wrong, but you don't get values like "fails when `amount = 5, balance = 3`."

This is because z3's model-based quantifier instantiation (mbqi) is disabled — enabling it causes infinite loops on the universally quantified map axioms.

## Struct fields through mappings

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
| Struct fields through mappings | Blocked on Strata Core heap parameterization |
| `old()` in loop invariants | `__old` marker not resolved in loop context |
| `block.timestamp` | No time abstraction yet |
| `msg.sender` in constructors | Constructor handling incomplete |
| External calls / reentrancy | No cross-contract reasoning |
| Assembly / inline Yul | Not parsed |
| Dynamic arrays (`push`/`pop`) | `.length` works, `push`/`pop` not modeled |
| Inheritance | Single contract only, no virtual dispatch |
| Lemmas (`@custom:strata lemma`) | Needs Laurel grammar extension |
