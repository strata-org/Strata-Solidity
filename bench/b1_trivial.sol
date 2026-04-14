// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Bench 1: Single variable, single function (baseline)
contract B1_Trivial {
    uint256 public x;

    /// @custom:strata ensures x == val
    function set(uint256 val) external {
        x = val;
    }
}
