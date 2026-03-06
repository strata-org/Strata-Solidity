// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract AssertFail {
    function bad(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 c = a + b;
        assert(c == a);  // Should fail when b != 0
        return c;
    }
}
