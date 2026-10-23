// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Block values advance between transactions without any function running,
// so checking the contract's functions cannot show that an invariant over
// them is preserved. The file is rejected.
contract InvariantBlockValue {
    /// @custom:strata invariant deadline > block.timestamp
    uint256 public deadline;

    constructor() {
        deadline = block.timestamp + 1 days;
    }
}
