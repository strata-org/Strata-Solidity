# Integers and Overflow

Solidity has fixed-size integer types (`uint8` through `uint256`, `int8` through `int256`). Since Solidity 0.8.0, arithmetic operations revert on overflow and underflow by default. StrataSolidity models this behavior.

## Checked arithmetic (default)

In checked mode (the default since Solidity 0.8.0), StrataSolidity treats overflow and underflow as revert conditions. If an addition could overflow, the verifier considers the revert path:

```solidity
/// @custom:strata ensures totalSupply == old(totalSupply) + amount
function mint(address to, uint256 amount) external {
    totalSupply += amount;  // reverts if overflow
    balances[to] += amount;
}
```

If `totalSupply + amount` could exceed `type(uint256).max`, the function reverts and the postcondition is vacuously satisfied (it only applies to non-reverting executions).

## Unchecked arithmetic

Inside `unchecked` blocks, overflow wraps silently:

```solidity
unchecked {
    totalSupply += amount;  // wraps on overflow, no revert
}
```

StrataSolidity models the wrapping behavior. If your postcondition assumes no wrapping occurred, you need a precondition to prevent it:

```solidity
/// @custom:strata requires totalSupply + amount <= type(uint256).max
/// @custom:strata ensures totalSupply == old(totalSupply) + amount
function mint(address to, uint256 amount) external {
    unchecked {
        totalSupply += amount;
    }
}
```

## Type constants

StrataSolidity supports `type(T).max` and `type(T).min` for all integer types:

```solidity
/// @custom:strata requires amount <= type(uint256).max - totalSupply
```

These are resolved to their compile-time constant values.

## Specification expressions

Expressions in specifications (`requires`, `ensures`, etc.) use mathematical integers — they do not overflow. This means you can write:

```solidity
/// @custom:strata ensures totalSupply == old(totalSupply) + amount
```

The `+` in the specification is mathematical addition, not Solidity's checked addition. The specification is about the *intended* behavior, not the machine arithmetic.
