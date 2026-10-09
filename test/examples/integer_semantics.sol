// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Integers behave as in Solidity: `unchecked` arithmetic wraps around, an
// explicit conversion truncates (two's complement), a `bytesN` conversion
// keeps the high-order bytes, signed `/` and `%` round toward zero, and a
// conversion to an enum reverts when out of range.
contract IntegerSemantics {
    enum Color { Red, Green }

    // Refuted: the sum wraps around to 0.
    function uncheckedAdd() external pure {
        uint256 a = type(uint256).max;
        uint256 c;
        unchecked { c = a + 1; }
        assert(c > a);
    }

    function uncheckedIncrement() external pure {
        uint8 i = 255;
        unchecked { i++; }
        assert(i == 0);
    }

    // Refuted: uint8(256) == 0.
    function narrowing(uint256 v) external pure {
        uint8 s = uint8(v);
        assert(s == v);
    }

    function narrowingRange(uint256 v) external pure {
        uint8 s = uint8(v);
        assert(s <= 255);
    }

    function signReinterpretation() external pure {
        int8 a = -1;
        assert(uint8(a) == 255);
        assert(int8(uint8(200)) == -56);
    }

    function signedDivision() external pure {
        int256 a = -7;
        int256 b = 2;
        assert(a / b == -3);
        assert(a % b == -1);
    }

    function bytesConversion(bytes32 h) external pure {
        bytes4 x = bytes4(h);
        assert(uint32(x) <= type(uint32).max);
    }

    function enumConversion(uint256 v) external pure returns (Color c) {
        c = Color(v);
        assert(v <= 1);
    }
}
