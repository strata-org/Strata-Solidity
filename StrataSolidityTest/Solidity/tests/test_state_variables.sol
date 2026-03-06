// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: State variables appear as fields in the contract CompositeType.
contract StateVars {
    uint256 public counter;
    bool public active;
    address public owner;

    function checkTypes(uint256 x) public pure returns (uint256) {
        assert(x >= 0);
        return x;
    }
}
