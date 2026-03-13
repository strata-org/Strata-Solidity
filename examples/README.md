# Verification Example Contracts

Demonstration contracts for testing Strata Solidity SARIF output. Each contract
uses `@custom:strata` NatSpec annotations and targets `pragma solidity ^0.8.0`.

## Examples

| File | Description | Expected Result |
|------|-------------|-----------------|
| `overflow_token.sol` | ERC20-like token with no bounds check on `mint` | **Fail** — `ensures` on `mint` can fail when `totalSupply + amount` overflows |
| `reentrancy_vulnerable.sol` | Vault that updates state after an external call | **Fail** — `ensures` on `withdraw` may fail under reentrant execution |
| `safe_token.sol` | Correctly specified token with bounded `mint` | **Pass** — all invariants and postconditions hold |
| `access_control.sol` | Ownable pattern missing a zero-address guard | **Pass** — spec is satisfied; the missing guard is a runtime concern, not a spec violation |

## Usage

Run the Strata verifier against any example:

```sh
strata verify examples/overflow_token.sol
```

Or verify all examples and inspect the SARIF output:

```sh
strata verify examples/ --format sarif -o results.sarif
```
