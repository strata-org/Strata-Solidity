// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Loop invariant with for-loop.
/// Tests that _strata_loop_invariant works with for loops.
contract LoopInvariantFor {

    /// Count up to n. Invariant: result == i at each iteration.
    function countUp(uint256 n) public pure returns (uint256 result) {
        require(n <= 1000, "n too large");
        result = 0;
        /// @custom:strata loop-invariant result == i
        for (uint256 i = 0; i < n; i++) {
            result += 1;
        }
    }
}
