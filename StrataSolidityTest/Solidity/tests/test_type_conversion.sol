// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TestTypeConversion {
    function testAddressZero() public pure returns (uint256) {
        address zero = address(0);
        assert(zero == address(0));
        return uint256(42);
    }
}
