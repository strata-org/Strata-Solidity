// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MultiStruct {
    struct Voter {
        uint256 weight;
        bool voted;
    }

    struct Proposal {
        uint256 voteCount;
    }

    function checkWeight(uint256 w) public pure returns (uint256) {
        assert(w + 1 > w);
        return w + 1;
    }
}
