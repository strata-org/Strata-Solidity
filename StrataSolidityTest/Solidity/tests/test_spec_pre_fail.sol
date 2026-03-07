// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Precondition failure at call site.
/// The callee requires x > 0, but the caller passes 0.
contract SpecPreFail {

    // Strata specification stubs
    function _strata_pre(bool) internal pure {}

    function needsPositive(uint256 x) public pure returns (uint256 result) {
        _strata_pre(x > 0);
        result = x - 1;
    }

    function badCaller() public pure returns (uint256 result) {
        result = needsPositive(0);
    }
}
