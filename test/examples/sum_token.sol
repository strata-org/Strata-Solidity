// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:strata invariant totalSupply == sum(balances)
contract SumToken {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    /// @custom:strata modifies balances[to], totalSupply
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    function mint(address to, uint256 amount) external {
        balances[to] += amount;
        totalSupply += amount;
    }

    /// @custom:strata requires from != to
    /// @custom:strata requires amount <= balances[from]
    /// @custom:strata modifies balances[from], balances[to]
    /// @custom:strata ensures balances[from] == old(balances[from]) - amount
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    function transfer(address from, address to, uint256 amount) external {
        require(from != to);
        require(amount <= balances[from]);
        balances[from] -= amount;
        balances[to] += amount;
    }
}
