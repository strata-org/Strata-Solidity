// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: compound assignment through storage reference.
/// delegate_.weight += sender.weight
contract StorageRefCompound {
    struct Voter {
        uint weight;
        bool voted;
    }

    mapping(address => Voter) public voters;

    function testCompound(address a, address b) public {
        Voter storage sender = voters[a];
        Voter storage delegate_ = voters[b];
        sender.weight = 5;
        delegate_.weight = 10;
        delegate_.weight += sender.weight;
        assert(delegate_.weight == 15);
    }
}
