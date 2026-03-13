// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title OverflowToken
/// @notice ERC20-like token with missing overflow guard on mint — should FAIL verification.
contract OverflowToken {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    function mint(address to, uint256 amount) external {
        // No require bounding amount — overflow possible in spec reasoning
        totalSupply += amount;
        balances[to] += amount;
    }
}
