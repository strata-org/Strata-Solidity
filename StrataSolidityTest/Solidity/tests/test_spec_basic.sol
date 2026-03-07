// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Basic specification tests for _strata_pre, _strata_post.
/// Pure functions only — no state variables or heap parameterization.
contract SpecBasic {

    // Strata specification stubs
    function _strata_pre(bool) internal pure {}
    function _strata_post(bool) internal pure {}

    /// Precondition: a and b must be small enough to avoid overflow.
    /// Postcondition: result equals a + b.
    function add(uint256 a, uint256 b) public pure returns (uint256 result) {
        _strata_pre(a <= 10000);
        _strata_pre(b <= 10000);
        _strata_post(result == a + b);

        result = a + b;
    }

    /// Postcondition: result is always >= a.
    function maxVal(uint256 a, uint256 b) public pure returns (uint256 result) {
        _strata_post(result >= a);

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
