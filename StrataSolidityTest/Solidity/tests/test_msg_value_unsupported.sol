// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Negative test: msg.value is not supported (only msg.sender).
/// Expected: translation error (unsupported).
contract MsgValueTest {
    function pay() public payable {
        require(msg.value > 0);
    }
}
