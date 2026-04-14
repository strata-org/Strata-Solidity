// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Bench 6: Two mappings, allowance pattern, 5 functions, quantifier-ready
contract B6_ERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;
    string public name;
    string public symbol;

    /// @custom:strata requires amount > 0
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    /// @custom:strata ensures balanceOf[to] == old(balanceOf[to]) + amount
    function mint(address to, uint256 amount) external {
        require(amount > 0);
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    /// @custom:strata requires to != msg.sender
    /// @custom:strata requires amount <= balanceOf[msg.sender]
    /// @custom:strata ensures balanceOf[msg.sender] == old(balanceOf[msg.sender]) - amount
    /// @custom:strata ensures balanceOf[to] == old(balanceOf[to]) + amount
    /// @custom:strata ensures totalSupply == old(totalSupply)
    function transfer(address to, uint256 amount) external {
        require(to != msg.sender);
        require(amount <= balanceOf[msg.sender]);
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    /// @custom:strata ensures allowance[msg.sender][spender] == amount
    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    /// @custom:strata requires to != from
    /// @custom:strata requires amount <= balanceOf[from]
    /// @custom:strata requires amount <= allowance[from][msg.sender]
    /// @custom:strata ensures balanceOf[from] == old(balanceOf[from]) - amount
    /// @custom:strata ensures balanceOf[to] == old(balanceOf[to]) + amount
    /// @custom:strata ensures allowance[from][msg.sender] == old(allowance[from][msg.sender]) - amount
    /// @custom:strata ensures totalSupply == old(totalSupply)
    function transferFrom(address from, address to, uint256 amount) external {
        require(to != from);
        require(amount <= balanceOf[from]);
        require(amount <= allowance[from][msg.sender]);
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
    }
}
