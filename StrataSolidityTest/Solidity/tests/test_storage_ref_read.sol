// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: storage reference reads should reflect mapping entry values.
/// Exercises the heap-parameterization path for FieldSelect on select() results.
/// Expected to fail until storage-reference read initialization is fixed (see
/// SolToLaurel.lean storage-ref LIMITATION comment).
contract StorageRefRead {
    struct Voter {
        uint weight;
        bool voted;
    }

    mapping(address => Voter) public voters;

    function giveRightToVote(address voter) public {
        require(voters[voter].weight == 0);
        voters[voter].weight = 1;
    }

    function checkWeight(address voter) public {
        require(voters[voter].weight == 1);
        Voter storage v = voters[voter];
        // This assertion should pass: v.weight reads from the mapping entry
        // where weight was just required to be 1.
        assert(v.weight == 1);
    }
}
