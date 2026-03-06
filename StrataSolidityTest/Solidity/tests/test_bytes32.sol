// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: bytes32 type translates as TInt (Phase 1 modeling).
contract Bytes32Test {
    function checkBytes32(bytes32 a, bytes32 b) public pure {
        require(a == b);
        assert(a == b);
    }
}
