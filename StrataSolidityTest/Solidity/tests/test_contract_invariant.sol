// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Contract invariant test with scalar state variable.
/// The invariant `x >= 10` is conjoined with every non-pure function's
/// pre- and postconditions. The constructor establishes it (x = 10) and
/// addOne preserves it. NOTE: `x >= 0` would be a tautology on uint256 —
/// the tool assumes non-negativity for unsigned state; the bound must be
/// something the type system does NOT give for the fixture to test the
/// invariant machinery.
/// (Attached to the state variable — contract-level NatSpec above the
/// `contract` keyword is intentionally ignored to avoid ambiguity in
/// multi-contract files; see ContractTranslator "Collect @custom:strata
/// invariant only from state variable NatSpec".)
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
