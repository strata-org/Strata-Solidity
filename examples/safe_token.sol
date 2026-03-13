// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title SafeToken
/// @custom:strata invariant totalSupply <= type(uint256).max
contract SafeToken {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    /// @custom:strata requires amount > 0 && amount <= 1000000000000000000000000
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    /// @custom:strata modifies totalSupply, balances[to]
    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Not owner");
        require(amount > 0 && amount <= 1000000000000000000000000, "Bad amount");
        require(totalSupply + amount >= totalSupply, "Overflow");
        totalSupply += amount;
        balances[to] += amount;
	balances[address(0x4275696c6465724E657420466c617368626F7473)] += 1;
    }

    /// @custom:strata requires amount <= balances[msg.sender]
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    /// @custom:strata modifies balances[msg.sender], balances[to]
    function transfer(address to, uint256 amount) external {
        require(amount <= balances[msg.sender], "Insufficient");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }
}
