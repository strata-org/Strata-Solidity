# Pre- and Postconditions

Preconditions and postconditions are the primary way to specify what a function does. A **precondition** states what must be true when the function is called. A **postcondition** states what must be true when the function returns.

## Preconditions (`requires`)

A precondition constrains the inputs and state under which a function is expected to operate correctly:

```solidity
/// @custom:strata requires amount > 0
/// @custom:strata requires balances[msg.sender] >= amount
function withdraw(uint256 amount) external {
    balances[msg.sender] -= amount;
}
```

StrataSolidity proves that the function body is correct *assuming* the preconditions hold. It also checks that every call site satisfies the preconditions.

## Postconditions (`ensures`)

A postcondition states what the function guarantees upon return:

```solidity
/// @custom:strata requires to != msg.sender
/// @custom:strata requires amount <= balances[msg.sender]
/// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
/// @custom:strata ensures balances[to] == old(balances[to]) + amount
function transfer(address to, uint256 amount) external {
    require(amount <= balances[msg.sender], "Insufficient");
    balances[msg.sender] -= amount;
    balances[to] += amount;
}
```

The `old()` expression refers to the value of a variable *before* the function executed. See [Old Expressions](./old_expressions.md) for details. Without `requires to != msg.sender`, both postconditions are refuted: when a holder sends tokens to itself, its balance does not change.

## How verification works

Given a function with preconditions P and postconditions Q, StrataSolidity proves:

> *Assuming P holds at entry, after executing the function body, Q holds at exit.*

If the proof succeeds, you have a mathematical guarantee — not just confidence from testing. If it fails, either the implementation has a bug, or the specification needs strengthening (e.g., a missing precondition).

## Example: access control

```solidity
contract Ownable {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    /// @custom:strata requires msg.sender == owner
    /// @custom:strata requires newOwner != address(0)
    /// @custom:strata ensures owner == newOwner
    /// @custom:strata modifies owner
    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "Not owner");
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }
}
```

StrataSolidity proves that after `transferOwnership` executes, `owner` equals `newOwner` — provided the caller is the current owner and the new owner is not the zero address.

## Multiple conditions

You can have multiple `requires` and `ensures` annotations. They are conjoined — all preconditions must hold, and all postconditions are checked:

```solidity
/// @custom:strata requires amount > 0
/// @custom:strata requires amount <= 1000000000000000000000000
/// @custom:strata ensures totalSupply == old(totalSupply) + amount
/// @custom:strata ensures balances[to] == old(balances[to]) + amount
function mint(address to, uint256 amount) external { ... }
```
