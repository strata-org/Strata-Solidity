// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Token {
    mapping(address => uint256) public balances;

    /// @custom:strata invariant totalSupply == sum(balances)
    uint256 public totalSupply;

    /// @custom:strata modifies balances[to], totalSupply
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    function mint(address to, uint256 amount) external {
        balances[to] += amount;   // bug: totalSupply is never updated
    }

    /// @custom:strata requires to != msg.sender
    /// @custom:strata requires balances[msg.sender] >= amount
    /// @custom:strata modifies balances[msg.sender], balances[to]
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    function transfer(address to, uint256 amount) external {
        require(to != msg.sender, "self-transfer disallowed");
        require(balances[msg.sender] >= amount, "insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }
}
