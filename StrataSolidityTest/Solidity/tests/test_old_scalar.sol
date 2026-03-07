// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title old() on scalar (non-mapping) state variables.
/// Regression test: _strata_old on scalar state vars accessed via
/// FieldSelect self "name" must reference pre-state, not current-state.
contract OldScalar {

    function _strata_post(bool) internal pure {}
    function _strata_old_uint(uint256) internal pure returns (uint256) { return 0; }

    uint256 public x;

    /// After adding amount, x == old(x) + amount.
    function addAmount(uint256 amount) external {
        _strata_post(x == _strata_old_uint(x) + amount);
        require(amount <= 1000, "too large");
        require(x <= 100000, "x too large");
        x = x + amount;
    }
}
