// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Internal function call whose return value is used in an expression.
/// Models the winnerName() → winningProposal() pattern from Ballot.sol.
contract InternalCallReturnUse {
    uint256 public bestIndex;
    uint256 public bestScore;

    function getBestIndex() public view returns (uint256) {
        return bestIndex;
    }

    /// Calls getBestIndex() and uses the result in an arithmetic expression.
    function getDoubledIndex() external view returns (uint256 result) {
        result = getBestIndex() + getBestIndex();
    }
}
