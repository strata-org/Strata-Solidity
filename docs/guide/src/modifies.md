# Frame Conditions (modifies)

A `modifies` clause declares which state variables a function is allowed to change. Anything not listed must remain unchanged. This is called a *frame condition* — it frames what can change and, by exclusion, what cannot.

## Declaring modifies

```solidity
/// @custom:strata modifies totalSupply, balances[to]
function mint(address to, uint256 amount) external {
    totalSupply += amount;
    balances[to] += amount;
}
```

StrataSolidity checks two things:
1. The function only writes to `totalSupply` and `balances[to]`.
2. All other state variables (and all other mapping keys) remain unchanged.

## Key-scoped modifies

For mappings, you can scope `modifies` to specific keys:

```solidity
/// @custom:strata modifies balances[msg.sender], balances[to]
function transfer(address to, uint256 amount) external {
    balances[msg.sender] -= amount;
    balances[to] += amount;
}
```

This proves that `transfer` only modifies the balances of the sender and receiver. The balance of every other address is guaranteed unchanged — without needing an explicit `forall` postcondition.

## modifies vs. forall postconditions

Key-scoped `modifies` and `forall` postconditions can express similar properties:

```solidity
// These two are equivalent:

// Option 1: modifies clause
/// @custom:strata modifies balances[msg.sender], balances[to]

// Option 2: explicit forall postcondition
/// @custom:strata ensures forall a : address :: (a != msg.sender && a != to) ==> balances[a] == old(balances[a])
```

The `modifies` clause is more concise and is checked automatically. Use `forall` postconditions when you need to express more complex frame properties that `modifies` cannot capture.

## Multiple state variables

List all modified state variables, separated by commas:

```solidity
/// @custom:strata modifies owner, totalSupply, balances[to]
function mintAndTransferOwnership(address to, uint256 amount, address newOwner) external {
    owner = newOwner;
    totalSupply += amount;
    balances[to] += amount;
}
```

## What happens without modifies?

If you omit the `modifies` clause, StrataSolidity does not check frame conditions for that function. Adding `modifies` is optional but strongly recommended — it catches unintended state mutations that postconditions alone might miss.
