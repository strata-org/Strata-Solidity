// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract HashFunctions {
    function hashConsistency(bytes memory data) public pure returns (bool) {
        bytes32 h1 = keccak256(data);
        bytes32 h2 = keccak256(data);
        assert(h1 == h2);
        return true;
    }
}
