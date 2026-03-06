// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Arithmetic {
    function safeAdd(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}
