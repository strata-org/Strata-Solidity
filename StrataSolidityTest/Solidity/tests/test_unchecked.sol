// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Unchecked {
    function wrappingAdd(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 c;
        unchecked {
            c = a + b;
        }
        assert(c == a + b);
        return c;
    }
}
