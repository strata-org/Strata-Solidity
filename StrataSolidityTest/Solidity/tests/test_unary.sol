// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Unary {
    function negate_int(int256 x) public pure returns (int256) {
        return -x;
    }

    function negate_bool(bool x) public pure returns (bool) {
        return !x;
    }
}
