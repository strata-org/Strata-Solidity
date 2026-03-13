// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExternal {
    function getValue() external returns (uint256);
}

contract TryCatchTest {
    uint256 public lastValue;

    function tryGet(IExternal ext) public {
        try ext.getValue() returns (uint256 val) {
            lastValue = val;
        } catch {
            lastValue = 0;
        }
    }
}
