// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Exercises Literal subdenomination through the real verification harness:
// number literals are multiplied by their unit factor (1 ether = 1e18,
// 1 days = 86400). Regression guard for PR #15 (expression extras).
contract Subdenomination {
    /// @custom:strata ensures r == 1000000000000000000
    function oneEther() external pure returns (uint256 r) {
        r = 1 ether;
    }

    /// @custom:strata ensures r == 90000
    function oneDayPlus() external pure returns (uint256 r) {
        r = 1 days + 1 hours;
    }
}
