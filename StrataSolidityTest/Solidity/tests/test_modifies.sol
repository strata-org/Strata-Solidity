// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Frame condition tests using @custom:strata modifies.
contract ModifiesSpec {

    uint256 public x;
    uint256 public y;

    /// Only modifies x; y should be unchanged.
    /// @custom:strata modifies x
    /// @custom:strata ensures x == 42
    function setX() external {
        x = 42;
    }
}
