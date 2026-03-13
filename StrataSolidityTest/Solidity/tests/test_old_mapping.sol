// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title old() on mapping state variables.
/// Tests that old() correctly references pre-state mapping values.
contract OldMapping {

    mapping(address => uint256) public balances;

    /// After adding `amount`, the new balance equals old balance + amount.
    /// @custom:strata requires balances[to] <= 100000
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    function deposit(address to, uint256 amount) external {

        require(amount <= 10000, "amount too large");
        balances[to] += amount;
    }
}
