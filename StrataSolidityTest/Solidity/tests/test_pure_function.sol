// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PureFunction {
    function abs_diff(uint256 a, uint256 b) public pure returns (uint256) {
        if (a >= b) {
            return a - b;
        } else {
            return b - a;
        }
    }

    function negate(bool x) public pure returns (bool) {
        return !x;
    }
}
