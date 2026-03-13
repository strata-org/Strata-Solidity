// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Basic specification tests for _strata_pre, _strata_post.
/// Pure functions only — no state variables or heap parameterization.
contract SpecBasic {

    /// Precondition: a and b must be small enough to avoid overflow.
    /// Postcondition: result equals a + b.
    /// @custom:strata requires a <= 10000
    /// @custom:strata requires b <= 10000
    /// @custom:strata ensures result == a + b
    function add(uint256 a, uint256 b) public pure returns (uint256 result) {

        result = a + b;
    }

    /// Postcondition: result is always >= a.
    /// @custom:strata ensures result >= a
    function maxVal(uint256 a, uint256 b) public pure returns (uint256 result) {

        if (a >= b) {
            result = a;
        } else {
            result = b;
        }
    }

    /// Precondition verified at call site: caller must pass valid args.
    function caller() public pure returns (uint256 result) {
        result = add(5, 3);
        assert(result == 8);
    }
}
