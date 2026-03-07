// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Internal call with return value used in assignment.
/// Models the winnerName() → winningProposal() pattern from Ballot.sol.
contract WinnerPattern {
    uint256 public bestIdx;

    function winningProposal() public view returns (uint256 winningProposal_) {
        winningProposal_ = bestIdx;
    }

    function winnerIndex() external view returns (uint256 winnerIdx_) {
        winnerIdx_ = winningProposal();
    }
}
