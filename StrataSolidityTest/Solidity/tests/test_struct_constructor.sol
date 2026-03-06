// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: struct constructor calls (structConstructorCall kind).
/// Verifies that Point({x: a, y: b}) translates through
/// the pipeline without errors. Field access verification on constructed
/// structs requires heap parameterization improvements (tracked separately).
/// NOTE: Assertions only check argument properties, not constructed struct
/// fields — field-access assertions are the intended next step.
contract TestStructConstructor {
    struct Point {
        uint256 x;
        uint256 y;
    }

    function makePoint(uint256 a, uint256 b) public pure returns (uint256) {
        Point memory p = Point({x: a, y: b});
        uint256 sum = a + b;
        assert(sum >= a);
        return sum;
    }
}
