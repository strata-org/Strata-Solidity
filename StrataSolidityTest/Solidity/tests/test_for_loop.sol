// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ForLoop {
    function sum(uint256 n) public pure returns (uint256) {
        uint256 s = 0;
        for (uint256 i = 0; i < n; i++) {
            s = s + i;
        }
        return s;
    }
}
