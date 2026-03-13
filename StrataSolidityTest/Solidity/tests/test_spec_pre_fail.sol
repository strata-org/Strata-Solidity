// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Precondition failure at call site.
/// The callee requires x > 0, but the caller passes 0.
contract SpecPreFail {

    /// @custom:strata requires x > 0
    function needsPositive(uint256 x) public pure returns (uint256 result) {
        result = x - 1;
    }

    function badCaller() public pure returns (uint256 result) {
        result = needsPositive(0);
    }
}
