// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Loop invariant verification test.
/// Simple summation loop with invariant and postcondition.
contract LoopInvariant {

    // Strata specification stubs
    function _strata_post(bool) internal pure {}
    function _strata_loop_invariant(bool) internal pure {}

    /// Sum n copies of step. Invariant: sum == i * step at each iteration.
    function sumSteps(uint256 n, uint256 step) public pure returns (uint256 sum) {
        _strata_post(sum == n * step);

        require(n <= 1000, "n too large");
        require(step <= 1000, "step too large");
        sum = 0;
        for (uint256 i = 0; i < n; i++) {
            _strata_loop_invariant(sum == i * step);
            sum += step;
        }
    }
}
