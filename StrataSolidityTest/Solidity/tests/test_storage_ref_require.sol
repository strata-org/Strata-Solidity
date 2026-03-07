// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: require and bool field through storage reference.
contract StorageRefRequire {
    struct Voter {
        uint weight;
        bool voted;
    }

    mapping(address => Voter) public voters;

    function testRequire(address addr) public {
        Voter storage sender = voters[addr];
        require(sender.weight != 0, "No right to vote");
        require(!sender.voted, "Already voted");
        sender.voted = true;
        assert(sender.voted);
    }
}
