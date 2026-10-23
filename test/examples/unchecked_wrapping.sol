// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// In `unchecked`, a signed division wraps (`type(int8).min / -1` is
// `type(int8).min`), and so does a power of named constants (`B ** 2` has
// type uint8). Both results used to stay unbounded, so `c > 0` and
// `c == 256` were proven.
contract UncheckedWrapping {
    uint8 constant B = 16;

    // Passes: type(int8).min / -1 wraps to type(int8).min.
    function divisionWraps(int8 a) external pure {
        require(a == type(int8).min);
        int8 c;
        unchecked { c = a / -1; }
        assert(c == -128);
    }

    // Refuted: claims the quotient is positive.
    function divisionWrong(int8 a) external pure {
        require(a == type(int8).min);
        int8 c;
        unchecked { c = a / -1; }
        assert(c > 0);
    }

    // Passes: `/=` wraps the same way.
    function compoundDivisionWraps(int8 a) external pure {
        require(a == type(int8).min);
        unchecked { a /= -1; }
        assert(a == -128);
    }

    // Refuted: claims `/=` did not wrap.
    function compoundDivisionWrong(int8 a) external pure {
        require(a == type(int8).min);
        unchecked { a /= -1; }
        assert(a > 0);
    }

    // Passes: B ** 2 is 256, which wraps to 0 in uint8.
    function powerWraps() external pure {
        uint8 c;
        unchecked { c = B ** 2; }
        assert(c == 0);
    }

    // Refuted: claims the power did not wrap.
    function powerWrong() external pure {
        uint256 c;
        unchecked { c = B ** 2; }
        assert(c == 256);
    }
}
