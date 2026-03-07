// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Chain of internal calls between view functions.
/// getSum calls getX, both read state.
contract InternalCallChain {
    uint256 public x;
    uint256 public y;

    function getX() public view returns (uint256) {
        return x;
    }

    function getSum() public view returns (uint256) {
        uint256 xVal = getX();
        return xVal + y;
    }

    function check() external view returns (uint256 result) {
        result = getSum();
    }
}
