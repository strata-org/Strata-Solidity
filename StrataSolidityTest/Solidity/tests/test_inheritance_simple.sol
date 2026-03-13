// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Simple inheritance — solc flattens inherited members into child AST.
contract Base {
    uint256 public value;

    function setValue(uint256 v) public {
        value = v;
    }
}

contract Child is Base {
    function increment() public {
        value = value + 1;
    }
}
