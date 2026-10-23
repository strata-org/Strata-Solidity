# Verification Example Contracts

Example Solidity contracts for trying StrataSolidity and its SARIF output.
They are not part of the test suite: `test/examples/` holds the fixtures
that CI checks.

All contracts use `@custom:strata` NatSpec annotations and `pragma solidity ^0.8.0`.

| File | Description | Expected Result |
|------|-------------|-----------------|
| `overflow_token.sol` | ERC20-like mint whose supply wraps around in `unchecked` | **Fail** (1 of 2 refuted) |
| `reentrancy_vulnerable.sol` | Withdraw with state update after external call | **Fail** (1 of 1 refuted) |
| `safe_token.sol` | Correctly specified token with invariant/requires/ensures/modifies | **Pass** (13 of 13) |
| `access_control.sol` | Ownable with transferOwnership | **Pass** (2 of 2) |
