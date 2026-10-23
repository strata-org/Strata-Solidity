# Old Expressions

The `old()` expression refers to the value of a variable or mapping entry *before* the function executed. It is used in postconditions to relate the post-state to the pre-state.

## Basic usage

```solidity
/// @custom:strata ensures totalSupply == old(totalSupply) + amount
function mint(address to, uint256 amount) external {
    totalSupply += amount;
}
```

`old(totalSupply)` is the value of `totalSupply` at function entry. The postcondition says: "the new total supply equals the old total supply plus the minted amount."

## Old with mappings

`old()` works with mapping access:

```solidity
/// @custom:strata requires to != msg.sender
/// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
/// @custom:strata ensures balances[to] == old(balances[to]) + amount
function transfer(address to, uint256 amount) external {
    balances[msg.sender] -= amount;
    balances[to] += amount;
}
```

(Without `requires to != msg.sender`, both postconditions are refuted: a
transfer to oneself leaves the balance unchanged.)

## Old with nested mappings

Nested mapping access inside `old()` is supported:

```solidity
/// @custom:strata ensures allowance[from][msg.sender] == old(allowance[from][msg.sender]) - amount
```

## Where old() can be used

- ✅ In `ensures` (postconditions)
- ✅ In `loop-invariant` annotations, where `old(e)` is also the value at the
  function's entry (not at the loop's entry)
- ✅ With scalar state variables, array lengths, and simple and nested
  mapping access
- ❌ In `invariant` annotations, which relate no two states (rejected, with a
  message)

## When to use old()

Use `old()` whenever a postcondition needs to describe *how* state changed, not just what the final state is:

```solidity
// "balance is zero" — no old() needed
/// @custom:strata ensures balances[msg.sender] == 0

// "balance decreased by amount" — old() needed
/// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
```

The second form is stronger — it says exactly how much the balance changed, not just what it ended up as.
