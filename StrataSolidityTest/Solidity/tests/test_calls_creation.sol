// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Child {
    uint256 public value;
    constructor(uint256 v) { value = v; }
}

contract CallsAndCreation {
    Child public child;
    uint256 public lastSent;

    function createChild(uint256 v) external {
        child = new Child(v);
    }

    function sendEther(address payable target, uint256 amount) external {
        target.call{value: amount, gas: 50000}("");
        lastSent = amount;
    }

    function allocateArray(uint256 n) external pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            arr[i] = i;
        }
        return arr;
    }
}
