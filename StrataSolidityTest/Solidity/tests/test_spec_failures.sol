// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Specification violation detection tests.
/// Each function has a spec that should FAIL verification.
/// @custom:strata invariant counter <= 100
contract SpecFailures {

    uint256 public counter;

    constructor() {
        // Contract invariant that will be violated by breakInvariant()
    }

    /// Postcondition that doesn't hold: claims result == a + b + 1, but body returns a + b.
    /// @custom:strata ensures res == a + b + 1
    function wrongPostcondition(uint256 a, uint256 b) public pure returns (uint256 res) {

        require(a <= 10000, "a too large");
        require(b <= 10000, "b too large");
        res = a + b;
    }

    /// Violates the contract invariant counter <= 100.
    /// Note: no explicit @custom:strata ensures here — the @custom:strata invariant declared in the
    /// constructor is automatically conjoined as a postcondition to every public/external
    /// function. This is the only test that exercises implicit invariant checking.
    function breakInvariant() external {
        counter = 200;
    }

    /// Loop invariant not maintained: claims sum <= i but body adds 2 each iteration.
    function badLoopInvariant(uint256 n) public pure returns (uint256 sum) {
        require(n <= 100, "n too large");
        sum = 0;
        /// @custom:strata loop-invariant sum <= i
        for (uint256 i = 0; i < n; i++) {
            sum += 2;
        }
    }
}
