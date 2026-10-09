// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Loop invariant verification test.
/// Simple summation loop with invariant and postcondition.
contract LoopInvariant {

    /// Sum n copies of step. Invariant: sum == i * step at each iteration.
    /// @custom:strata ensures sum == n * step
    /// @custom:strata loop-invariant i <= n
    /// @custom:strata loop-invariant sum == i * step
    function sumSteps(uint256 n, uint256 step) public pure returns (uint256 sum) {

        require(n <= 1000, "n too large");
        require(step <= 1000, "step too large");
        sum = 0;
        for (uint256 i = 0; i < n; i++) {
            sum += step;
        }
    }
}
