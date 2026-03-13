// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Contract invariant test with scalar state variable.
/// The invariant `x >= 0` is conjoined with every non-pure function's
/// pre- and postconditions. The constructor establishes it.
/// @custom:strata invariant x >= 0
contract ContractInvariant {

    uint256 public x;

    constructor() {
        x = 10;
    }

    /// This function maintains the invariant: x stays >= 0.
    function addOne() external {
        x = x + 1;
    }

    /// Pure functions are NOT checked against the invariant.
    function pureAdd(uint256 a, uint256 b) public pure returns (uint256 result) {
        result = a + b;
    }
}
