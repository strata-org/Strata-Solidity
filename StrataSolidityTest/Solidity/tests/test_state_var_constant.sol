// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Constant state variable should be folded (not a field).
contract WithConstant {
    uint256 public constant MAX = 100;
    uint256 public value;

    function checkBound(uint256 x) public pure returns (uint256) {
        require(x <= MAX);
        assert(x <= 100);
        return x;
    }
}
