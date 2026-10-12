// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:strata invariant totalSupply <= MAX_SUPPLY
contract Token {
    uint256 public constant MAX_SUPPLY = 1000000;
    uint256 public totalSupply;

    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    function mint(uint256 amount) public {
        require(totalSupply + amount <= MAX_SUPPLY);
        totalSupply += amount;
    }
}
