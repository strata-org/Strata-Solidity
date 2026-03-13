// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title OverflowToken — ERC20-like token with a deliberate overflow bug
/// @notice The mint function lacks bounds checking on amount, so the
///         ensures postcondition can fail when totalSupply overflows.
contract OverflowToken {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    /// @custom:strata modifies totalSupply, balances
    function mint(address to, uint256 amount) external {
        // BUG: no overflow check — totalSupply + amount can wrap
        totalSupply += amount;
        balances[to] += amount;
    }

    /// @custom:strata requires balances[msg.sender] >= amount
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    /// @custom:strata ensures totalSupply == old(totalSupply) - amount
    /// @custom:strata modifies totalSupply, balances
    function burn(uint256 amount) external {
        require(balances[msg.sender] >= amount, "insufficient balance");
        balances[msg.sender] -= amount;
        totalSupply -= amount;
    }
}
