// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: UserDefinedTypeName in variable declarations.
contract TestUserDefinedType {
    struct Point {
        uint256 x;
        uint256 y;
    }

    function sumCoords(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 sum = a + b;
        assert(sum >= a);
        return sum;
    }
}
