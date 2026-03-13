// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Loop invariant with while-loop.
/// Tests that _strata_loop_invariant works with while loops.
contract LoopInvariantWhile {

    /// Multiply by repeated addition. Invariant: result == i * b.
    function multiply(uint256 a, uint256 b) public pure returns (uint256 result) {
        require(a <= 100, "a too large");
        require(b <= 100, "b too large");
        result = 0;
        uint256 i = 0;
        /// @custom:strata loop-invariant result == i * b
        while (i < a) {
            result += b;
            i += 1;
        }
    }
}
