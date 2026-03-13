// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Function overriding — child overrides virtual parent function.
contract Base {
    uint256 public value;

    function getValue() public virtual view returns (uint256) {
        return value;
    }
}

contract Child is Base {
    function getValue() public override view returns (uint256) {
        return value + 1;
    }
}
