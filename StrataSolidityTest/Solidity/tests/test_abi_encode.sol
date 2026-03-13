// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract AbiEncode {
    function encodeConsistency(uint256 a, uint256 b) public pure returns (bool) {
        bytes memory e1 = abi.encode(a, b);
        bytes memory e2 = abi.encode(a, b);
        assert(keccak256(e1) == keccak256(e2));
        return true;
    }

    function encodePacked(uint256 x) public pure returns (bytes memory) {
        return abi.encodePacked(x);
    }
}
