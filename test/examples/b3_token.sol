// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Bench 3: Mapping + multiple functions + invariant
contract B3_Token {
    mapping(address => uint256) public balances;

    /// @custom:strata invariant totalSupply == sum(balances)
    uint256 public totalSupply;

    /// @custom:strata requires amount > 0
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    function mint(address to, uint256 amount) external {
        require(amount > 0, "zero");
        totalSupply += amount;
        balances[to] += amount;
    }

    /// @custom:strata requires amount > 0
    /// @custom:strata requires amount <= balances[from]
    /// @custom:strata ensures totalSupply == old(totalSupply) - amount
    /// @custom:strata ensures balances[from] == old(balances[from]) - amount
    function burn(address from, uint256 amount) external {
        require(amount > 0, "zero");
        require(amount <= balances[from], "insufficient");
        totalSupply -= amount;
        balances[from] -= amount;
    }

    /// @custom:strata requires to != msg.sender
    /// @custom:strata requires amount <= balances[msg.sender]
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    function transfer(address to, uint256 amount) external {
        require(to != msg.sender, "self");
        require(amount <= balances[msg.sender], "insufficient");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }
}
