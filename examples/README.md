# Verification Example Contracts

Example Solidity contracts for testing Strata verification SARIF output.

All contracts use `@custom:strata` NatSpec annotations and `pragma solidity ^0.8.0`.

| File | Description | Expected Result |
|------|-------------|-----------------|
| `overflow_token.sol` | ERC20-like mint with no overflow guard | **Fail** |
| `reentrancy_vulnerable.sol` | Withdraw with state update after external call | **Fail** |
| `safe_token.sol` | Correctly specified token with invariant/requires/ensures/modifies | **Pass** |
| `access_control.sol` | Ownable with transferOwnership | **Pass** |
