# Quantifiers

Quantifiers let you make statements about *all* values of a type or assert that *some* value exists satisfying a property. They are essential for specifying properties over mappings, where you need to reason about every possible key.

## Universal quantifier (`forall`)

The `forall` quantifier states that a property holds for every value of a given type:

```solidity
/// @custom:strata ensures forall a : address :: balances[a] >= 0
```

This says: "after this function executes, every address has a non-negative balance." The verifier checks this for *all* possible addresses — not just a sample.

## Existential quantifier (`exists`)

The `exists` quantifier states that at least one value satisfying a property exists:

```solidity
/// @custom:strata ensures exists a : address :: balances[a] > 0
```

This says: "after this function executes, at least one address has a positive balance."

## Implication with quantifiers

Quantifiers are most powerful when combined with implication (`==>`). This pattern lets you say "for all addresses *except* these specific ones, nothing changed":

```solidity
/// @custom:strata requires balances[msg.sender] >= amount
/// @custom:strata requires to != msg.sender
/// @custom:strata ensures balances[to] == old(balances[to]) + amount
/// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
/// @custom:strata ensures forall a : address :: (a != msg.sender && a != to) ==> balances[a] == old(balances[a])
/// @custom:strata modifies balances[msg.sender], balances[to]
function transfer(address to, uint256 amount) external {
    require(to != msg.sender, "self-transfer");
    require(balances[msg.sender] >= amount, "Insufficient");
    balances[msg.sender] -= amount;
    balances[to] += amount;
}
```

The last `ensures` line is the key: it proves that a transfer between two addresses does not modify the balance of *any other address*. This is a frame property — it says what *didn't* change, which is just as important as saying what did.

## When to use quantifiers

- **Proving no side effects:** "no balance other than sender and receiver changed" (as above).
- **Global properties:** "all balances are non-negative."
- **Sorted or ordered data:** "for all indices i < j, values[i] <= values[j]."

Quantifiers over infinite domains (like `address`) cannot be checked by enumeration — they require logical reasoning by the SMT solver. This is what makes formal verification fundamentally different from testing.
