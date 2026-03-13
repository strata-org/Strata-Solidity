// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Loop invariant verification test.
/// Simple summation loop with invariant and postcondition.
contract LoopInvariant {

    /// Sum n copies of step. Invariant: sum == i * step at each iteration.
    /// @custom:strata ensures sum == n * step
    function sumSteps(uint256 n, uint256 step) public pure returns (uint256 sum) {

        require(n <= 1000, "n too large");
        require(step <= 1000, "step too large");
        sum = 0;
        /// @custom:strata loop-invariant sum == i * step
        for (uint256 i = 0; i < n; i++) {
            sum += step;
        }
    }
}
