// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

/// Test: user-defined value type with wrap/unwrap (identity for verification).
type UFixed256x18 is uint256;

contract TestUserDefinedValueType {
    function identity(uint256 x) public pure returns (uint256) {
        UFixed256x18 wrapped = UFixed256x18.wrap(x);
        uint256 unwrapped = UFixed256x18.unwrap(wrapped);
        assert(unwrapped == x);
        return unwrapped;
    }
}
