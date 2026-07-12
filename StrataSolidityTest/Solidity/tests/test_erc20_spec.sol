// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Minimal ERC20-like token with full contract specification.
/// Demonstrates contract invariants, pre/postconditions, and old().
contract ERC20Spec {

    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    constructor() {
        // Contract invariant: total supply is non-negative
    }

    /// @custom:strata requires balances[to] <= 100000
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    function mint(address to, uint256 amount) external {

        require(amount <= 10000, "amount too large");
        require(totalSupply <= 100000, "supply too large");
        totalSupply += amount;
        balances[to] += amount;
    }

    /// @custom:strata requires balances[msg.sender] >= amount
    /// @custom:strata requires to != msg.sender
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    function transfer(address to, uint256 amount) external {

        require(to != msg.sender, "self-transfer disallowed");
        require(balances[msg.sender] >= amount, "insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }
}
