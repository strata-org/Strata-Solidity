// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// Array of structs: Proposal[] like in the Ballot contract.
contract ArrayStruct {
    struct Proposal {
        uint voteCount;
    }

    Proposal[] public proposals;

    function getProposalCount() public view returns (uint) {
        return proposals.length;
    }
}
