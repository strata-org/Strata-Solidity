// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract EventTest {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed to, uint256 value);

    error InsufficientBalance(uint256 available, uint256 required);
    error ZeroAddress();

    /// @custom:strata modifies balances[msg.sender], balances[to]
    /// @custom:strata requires to != msg.sender
    /// @custom:strata requires amount <= balances[msg.sender]
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    function transfer(address to, uint256 amount) external {
        if (to == address(0)) revert ZeroAddress();
        if (amount > balances[msg.sender]) revert InsufficientBalance(balances[msg.sender], amount);
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
    }

    /// @custom:strata modifies balances[to], totalSupply
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    function mint(address to, uint256 amount) external {
        balances[to] += amount;
        totalSupply += amount;
        emit Mint(to, amount);
    }
}
