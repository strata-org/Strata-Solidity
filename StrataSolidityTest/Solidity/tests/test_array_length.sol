// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// Pure function operating on a memory array parameter.
contract ArrayLength {
    function checkLength(uint[] memory arr) public pure returns (uint) {
        return arr.length;
    }
}
