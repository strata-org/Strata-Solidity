// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract WhileLoop {
    function sumTo(uint256 n) public pure returns (uint256) {
        uint256 i = 0;
        uint256 s = 0;
        while (i < n) {
            i = i + 1;
            s = s + i;
        }
        return s;
    }
}
