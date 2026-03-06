// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ControlFlow {
    function max(uint256 a, uint256 b) public pure returns (uint256) {
        if (a >= b) {
            return a;
        } else {
            return b;
        }
    }
}
