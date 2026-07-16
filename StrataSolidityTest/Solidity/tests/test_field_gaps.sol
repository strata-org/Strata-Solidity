// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Exercises field-level metadata additions (#17): abstract contract,
// virtual/override functions, immutable state var, explicit visibility.
// These are metadata that must not break translation.

abstract contract Base {
    /// @custom:strata ensures r == x
    function echo(uint256 x) external pure virtual returns (uint256 r);
}

contract Derived is Base {
    uint256 private _supply;

    /// @custom:strata ensures r == x
    function echo(uint256 x) external pure override returns (uint256 r) {
        r = x;
    }

    /// @custom:strata ensures _supply == old(_supply) + amount
    function mint(uint256 amount) external {
        _supply = _supply + amount;
    }
}
