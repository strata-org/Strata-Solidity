// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test that a failing assertion produces SARIF output with counterexample data.
contract CounterexampleTest {
    /// @custom:strata ensures \result == a - b
    function subtract(uint256 a, uint256 b) public pure returns (uint256) {
        return a + b; // intentionally wrong: should be a - b
    }
}
