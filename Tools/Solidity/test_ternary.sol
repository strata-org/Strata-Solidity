// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TernaryTest {
    function max(uint256 a, uint256 b) public pure returns (uint256) {
        return a >= b ? a : b;
    }

    function abs(int256 x) public pure returns (int256) {
        return x >= 0 ? x : -x;
    }
}
