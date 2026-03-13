// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Simple contract for SARIF output validation: one pass, one fail.

contract SarifTest {
    /// @custom:strata ensures \result == a + b
    function good(uint256 a, uint256 b) public pure returns (uint256) {
        return a + b;
    }

    /// @custom:strata ensures \result == a * b
    function bad(uint256 a, uint256 b) public pure returns (uint256) {
        return a + b; // intentionally wrong
    }
}
