// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Contract with only state variables and no functions.
/// Edge case: CompositeType has fields but no procedures.
contract OnlyState {
    uint256 public x;
    bool public flag;
}
