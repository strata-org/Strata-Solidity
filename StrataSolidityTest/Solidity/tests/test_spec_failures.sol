// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Specification violation detection tests.
/// Each function has a spec that should FAIL verification.
contract SpecFailures {

    // Strata specification stubs
    function _strata_post(bool) internal pure {}
    function _strata_loop_invariant(bool) internal pure {}
    function _strata_invariant(bool) internal pure {}

    uint256 public counter;

    constructor() {
        // Contract invariant that will be violated by breakInvariant()
        _strata_invariant(counter <= 100);
    }

    /// Postcondition that doesn't hold: claims result == a + b + 1, but body returns a + b.
    function wrongPostcondition(uint256 a, uint256 b) public pure returns (uint256 res) {
        _strata_post(res == a + b + 1);

        require(a <= 10000, "a too large");
        require(b <= 10000, "b too large");
        res = a + b;
    }

    /// Violates the contract invariant counter <= 100.
    function breakInvariant() external {
        counter = 200;
    }

    /// Loop invariant not maintained: claims sum <= i but body adds 2 each iteration.
    function badLoopInvariant(uint256 n) public pure returns (uint256 sum) {
        require(n <= 100, "n too large");
        sum = 0;
        for (uint256 i = 0; i < n; i++) {
            _strata_loop_invariant(sum <= i);
            sum += 2;
        }
    }
}
