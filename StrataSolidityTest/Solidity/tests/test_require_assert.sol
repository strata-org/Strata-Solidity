// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract RequireAssert {
    function bounded_add(uint256 a, uint256 b) public pure returns (uint256) {
        require(a <= 100, "a too large");
        require(b <= 100, "b too large");
        uint256 c = a + b;
        assert(c <= 200);
        return c;
    }
}
