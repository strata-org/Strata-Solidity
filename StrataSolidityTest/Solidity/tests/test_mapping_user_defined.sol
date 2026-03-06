// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// Mapping with user-defined value type: mapping(address => Voter).
contract MappingUserDefined {
    struct Voter {
        uint weight;
        bool voted;
    }

    mapping(address => Voter) public voters;

    function setWeight(address voter, uint w) public {
        voters[voter].weight = w;
        assert(voters[voter].weight == w);
    }
}
