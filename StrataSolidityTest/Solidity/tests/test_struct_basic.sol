// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract StructBasic {
    struct Point {
        uint256 x;
        uint256 y;
    }

    function checkPoint(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 sum = a + b;
        assert(sum >= a);
        return sum;
    }
}
