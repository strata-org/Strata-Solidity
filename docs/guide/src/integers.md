# Integers and Overflow

Solidity has fixed-size integer types (`uint8` through `uint256`, `int8` through `int256`). Since Solidity 0.8.0, arithmetic operations revert on overflow and underflow by default.

Every value StrataSolidity reads (a parameter, a state variable, `msg.value`, …) is assumed to be in the range of its type.

## Checked arithmetic (default)

In checked mode (the default since Solidity 0.8.0), StrataSolidity computes with mathematical integers: a result that overflows is not wrapped. In Solidity that execution reverts; the verifier also considers it continuing with the out-of-range value, which can only add behaviours: a property that holds is never reported as violated because of it, but one that relies on the revert (e.g. a result being at most `type(uint256).max`) may not be proven.

```solidity
/// @custom:strata ensures totalSupply == old(totalSupply) + amount
function mint(address to, uint256 amount) external {
    totalSupply += amount;  // reverts if overflow
    balances[to] += amount;
}
```

If `totalSupply + amount` could exceed `type(uint256).max`, the function reverts in Solidity; the postcondition holds either way.

## Unchecked arithmetic

Inside `unchecked` blocks, overflow wraps silently:

```solidity
unchecked {
    totalSupply += amount;  // wraps on overflow, no revert
}
```

StrataSolidity models the wrapping (`+`, `-`, `*`, `++`, `--`, unary `-` and `op=`, within the operands' type). If your postcondition assumes no wrapping occurred, you need a precondition to prevent it:

```solidity
/// @custom:strata requires totalSupply + amount <= type(uint256).max
/// @custom:strata ensures totalSupply == old(totalSupply) + amount
function mint(address to, uint256 amount) external {
    unchecked {
        totalSupply += amount;
    }
}
```

## Conversions and division

An explicit conversion behaves as on the EVM:

- to a narrower or differently signed integer type, it truncates in two's complement (`uint8(300) == 44`, `int8(uint8(200)) == -56`); widening keeps the value;
- `bytesN` to a shorter `bytesM` keeps the high-order bytes, to a longer one pads on the right;
- to an enum, a value out of range reverts.

Signed `/` and `%` round toward zero (`-7 / 2 == -3`, `-7 % 2 == -1`). A power of constants (`2 ** 64`) is folded; a shift by a constant is a division (`>>`) or a wrapping multiplication (`<<`), and an unsigned `x & (2^n - 1)` keeps the low `n` bits. Other bitwise operations are uninterpreted functions.

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

`/` and `%` divide as in Solidity: `/` rounds toward zero and `%` takes the sign of the dividend (`-7 / 2 == -3`, `-7 % 2 == -1`), so a specification divides like the code it describes.
