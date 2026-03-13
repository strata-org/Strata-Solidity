// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title old() on scalar (non-mapping) state variables.
/// Regression test: _strata_old on scalar state vars accessed via
/// FieldSelect self "name" must reference pre-state, not current-state.
contract OldScalar {

    uint256 public x;

    /// After adding amount, x == old(x) + amount.
    /// @custom:strata ensures x == old(x) + amount
    function addAmount(uint256 amount) external {
        require(amount <= 1000, "too large");
        require(x <= 100000, "x too large");
        x = x + amount;
    }
}
