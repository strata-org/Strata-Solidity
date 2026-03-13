// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:strata invariant totalSupply >= 0
contract Token {
    uint256 public totalSupply;

    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    function mint(uint256 amount) public {
        totalSupply += amount;
    }
}
