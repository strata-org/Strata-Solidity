// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A bitwise result has the type of the operation. An uninterpreted result
// (`&`, `|`, `^`, a shift by a variable) used to lie in [0, 2^256), so a
// signed one was never negative and `(a & a) >= 0` was proven for a == -1;
// `~x` was uninterpreted. Now `~x` is exact, and an uninterpreted result
// ranges over the values of its type.
contract BitwiseTypes {
    // Passes: ~x is -x - 1 for a signed x.
    function notSigned() external pure {
        int8 x = 0;
        assert(~x == -1);
    }

    // Refuted: ~0 is negative for a signed type.
    function notSignedWrong() external pure {
        int8 x = 0;
        assert(~x >= 0);
    }

    // Passes: ~x is 255 - x for a uint8 x.
    function notUnsigned(uint8 x) external pure {
        assert(~x == 255 - x);
    }

    // Refuted: ~0 is 255.
    function notUnsignedWrong(uint8 x) external pure {
        assert(~x < 255);
    }

    // Refuted: -1 & -1 is -1.
    function andSigned(int8 a) external pure {
        require(a == -1);
        assert((a & a) >= 0);
    }

    // Refuted: -1 | 0 is -1.
    function orSigned(int8 a) external pure {
        require(a == -1);
        assert((a | 0) >= 0);
    }

    // Refuted: -1 >> n is -1 (an arithmetic shift).
    function shiftSigned(int8 a, uint8 n) external pure {
        require(a == -1);
        assert((a >> n) >= 0);
    }

    // Refuted: `&=` leaves -1 & -1, which is -1.
    function andAssignSigned(int8 a) external pure {
        require(a == -1);
        a &= a;
        assert(a >= 0);
    }

    // Passes: a signed bitwise result lies in its type.
    function andSignedInRange(int8 a, int8 b) external pure {
        assert((a & b) >= -128 && (a & b) <= 127);
    }

    // Passes: an unsigned one too.
    function andInRange(uint8 a, uint8 b) external pure {
        assert((a & b) <= 255);
    }

    // Refuted: 0 & 0 is 0.
    function andInRangeWrong(uint8 a, uint8 b) external pure {
        assert((a & b) >= 1);
    }
}
