// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title SafeToken — Correctly specified token that should pass all checks
/// @custom:strata invariant totalSupply >= 0
contract SafeToken {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    /// @custom:strata requires amount <= 10000
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    /// @custom:strata modifies totalSupply, balances
    function mint(address to, uint256 amount) external {
        require(amount <= 10000, "amount too large");
        totalSupply += amount;
        balances[to] += amount;
    }

    /// @custom:strata requires balances[msg.sender] >= amount
    /// @custom:strata ensures totalSupply == old(totalSupply) - amount
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    /// @custom:strata modifies totalSupply, balances
    function burn(uint256 amount) external {
        require(balances[msg.sender] >= amount, "insufficient balance");
        balances[msg.sender] -= amount;
        totalSupply -= amount;
    }
}
