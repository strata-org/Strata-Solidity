// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Rejected: assigning a tuple to existing variables (`(a, b) = (b, a)`)
// stops the translation of the whole file; a tuple declaration
// (`(uint256 a, uint256 b) = f();`) works. Gap `tuple-assignment` in
// docs/capabilities.toml.
contract GapTupleAssignment {
    /// @custom:strata ensures ra == b && rb == a
    function swap(uint256 a, uint256 b) external pure returns (uint256 ra, uint256 rb) {
        (ra, rb) = (b, a);
    }
}
