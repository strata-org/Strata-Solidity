// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: storage reference variable read/write through alias.
/// Reads and writes through the alias use per-field scalar variables.
contract StorageRefBasic {
    struct Voter {
        uint weight;
        bool voted;
    }

    mapping(address => Voter) public voters;

    function testStorageRef(address addr) public {
        Voter storage v = voters[addr];
        v.weight = 10;
        v.voted = true;
        assert(v.weight == 10);
    }
}
