// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: msg.value is available in non-pure functions.
contract MsgValueTest {
    function deposit(uint256 balance) public payable returns (uint256 newBalance) {
        require(msg.value > 0);
        newBalance = balance + msg.value;
        assert(newBalance >= balance);
    }
}
