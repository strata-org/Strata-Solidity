// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MultipleFunctions {
    function add_checked(uint256 a, uint256 b) public pure returns (uint256) {
        require(a <= 1000, "a too large");
        require(b <= 1000, "b too large");
        uint256 c = a + b;
        assert(c <= 2000);
        return c;
    }

    function sub_checked(uint256 a, uint256 b) public pure returns (uint256) {
        require(a >= b, "underflow");
        uint256 c = a - b;
        assert(c <= a);
        return c;
    }

    function is_even(uint256 x) public pure returns (bool) {
        return x % 2 == 0;
    }
}
