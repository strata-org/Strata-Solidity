// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract InternalCall {
    uint256 public value;

    function getValue() public view returns (uint256) {
        return value;
    }

    function checkValue() external view returns (uint256 result) {
        result = getValue();
    }
}
