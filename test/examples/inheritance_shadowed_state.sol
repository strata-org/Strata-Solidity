// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A derived contract may declare a state variable named like a private one
// of a base: they are different variables, in different storage slots.
// Verifying the flattening would merge them, so the file is rejected.

contract Base {
    uint256 private x;

    function setBase() external {
        x = 1;
    }
}

contract Derived is Base {
    uint256 public x;
}
