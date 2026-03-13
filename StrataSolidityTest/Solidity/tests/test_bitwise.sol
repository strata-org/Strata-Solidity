// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Bitwise {
    function bitwiseOps(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 r = a & b;
        r = r | b;
        r = r ^ a;
        r = a << 2;
        r = b >> 1;
        r = ~a;
        return r;
    }
}
