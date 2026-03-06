// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Require {
    function safeSub(uint256 a, uint256 b) public pure returns (uint256) {
        require(a >= b, "underflow");
        uint256 c = a - b;
        assert(c <= a);
        return c;
    }
}
