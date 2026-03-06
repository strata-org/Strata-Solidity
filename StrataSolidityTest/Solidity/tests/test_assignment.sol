// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract AssignOps {
    function test_assign(uint256 x) public pure returns (uint256) {
        uint256 y = x;
        y = y + 1;
        return y;
    }
}
