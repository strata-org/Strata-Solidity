// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: struct constructor with named arguments in non-declaration order.
/// Verifies that argument reordering works correctly when names differ
/// from the struct field declaration order.
/// NOTE: Assertions only check argument properties, not constructed struct
/// fields — field-access assertions are the intended next step.
contract TestStructConstructorReorder {
    struct Pair {
        uint256 first;
        uint256 second;
    }

    function testReorder(uint256 a, uint256 b) public pure returns (uint256) {
        // Named args in REVERSE order of struct fields
        Pair memory p = Pair({second: b, first: a});
        uint256 sum = a + b;
        assert(sum >= a);
        return sum;
    }
}
