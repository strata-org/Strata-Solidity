// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A power of constants is folded (`2 ** 64`); a shift by a constant is a
// division or a wrapping multiplication; an unsigned `x & (2^n - 1)` keeps
// the low `n` bits. Other bitwise operations remain uninterpreted.
contract ConstantBits {
    uint256 constant MASK64 = 2 ** 64 - 1;

    function power() external pure {
        assert(MASK64 == 18446744073709551615);
    }

    function selector(bytes32 h) external pure returns (uint256 s) {
        s = uint256(h) >> 224;
        assert(s < 2 ** 32);
    }

    // Refuted: the shift drops the high bits.
    function shiftLeft(uint8 x) external pure returns (uint8 y) {
        y = x << 4;
        assert(y >= x);
    }

    function lowBits(uint256 x) external pure returns (uint256 y) {
        y = x & 0xff;
        assert(y <= 255);
    }
}
