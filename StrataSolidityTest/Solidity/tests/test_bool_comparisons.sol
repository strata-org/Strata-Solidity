// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract BoolComparisons {
    function test_and_or(bool a, bool b) public pure returns (bool) {
        bool c = a && b;
        bool d = a || b;
        assert(!c || d);  // (a && b) implies (a || b)
        return d;
    }

    function test_eq(uint256 x, uint256 y) public pure returns (bool) {
        if (x == y) {
            assert(x >= y);
        }
        return x == y;
    }

    function test_comparisons(uint256 x, uint256 y) public pure returns (bool) {
        if (x > y) {
            assert(x != y);
            assert(x >= y);
        }
        if (x < y) {
            assert(x != y);
            assert(x <= y);
        }
        return x > y;
    }

    function test_bool_fail(bool a) public pure returns (bool) {
        bool c = a && true;
        assert(c != a);  // Should fail: (a && true) == a
        return c;
    }
}
