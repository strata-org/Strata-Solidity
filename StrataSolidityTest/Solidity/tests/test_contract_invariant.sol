// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Contract invariant test with scalar state variable.
/// The invariant `x >= 10` is assumed on entry to and re-established on
/// exit from every public/external state-changing function. The
/// constructor establishes it (x = 10) and addOne preserves it. NOTE:
/// `x >= 0` would be a tautology on uint256 — the tool assumes
/// non-negativity for unsigned state; the bound must be something the type
/// system does NOT give for the fixture to test the invariant machinery.
/// (Attached to the state variable; NatSpec above `contract` works too.)
contract ContractInvariant {

    /// @custom:strata invariant x >= 10
    uint256 public x;

    constructor() {
        x = 10;
    }

    /// This function maintains the invariant: x only grows from 10.
    function addOne() external {
        x = x + 1;
    }

    /// Pure functions are NOT checked against the invariant.
    function pureAdd(uint256 a, uint256 b) public pure returns (uint256 result) {
        result = a + b;
    }
}
