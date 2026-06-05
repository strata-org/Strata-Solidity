// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Regression guard for the field-level metadata additions (#17): abstract
// contract, virtual/override functions, explicit visibility. The metadata
// must not break translation; specs on the concrete contract still verify.

abstract contract Base {
    /// @custom:strata requires x >= 0
    /// @custom:strata ensures r == x
    function echo(uint256 x) external pure virtual returns (uint256 r);
}

contract FieldGaps is Base {
    uint256 private _supply;

    /// @custom:strata ensures r == x
    function echo(uint256 x) external pure override returns (uint256 r) {
        r = x;
    }

    /// @custom:strata requires amount >= 0
    /// @custom:strata ensures _supply == old(_supply) + amount
    function mint(uint256 amount) external {
        _supply = _supply + amount;
    }
}
