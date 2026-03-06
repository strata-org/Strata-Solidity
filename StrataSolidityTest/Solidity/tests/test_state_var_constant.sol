// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Constant state variable should produce isMutable = false.
contract WithConstant {
    uint256 public constant MAX = 100;
    uint256 public value;

    function checkBound(uint256 x) public pure returns (uint256) {
        require(x <= 100);
        assert(x >= 0);
        return x;
    }
}
