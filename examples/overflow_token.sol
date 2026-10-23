// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title OverflowToken
/// @notice ERC20-like token whose mint can overflow — should FAIL verification.
/// In `unchecked`, `totalSupply += amount` wraps around instead of reverting,
/// so the new supply can be smaller than the old one.
contract OverflowToken {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    function mint(address to, uint256 amount) external {
        unchecked {
            totalSupply += amount; // wraps on overflow
        }
        balances[to] += amount;
    }
}
