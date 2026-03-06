// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MsgSenderTest {
    /// msg.sender is available in non-pure functions.
    /// Verify that msg.sender equality is reflexive.
    function checkSender(address expected) public view {
        require(msg.sender == expected);
        assert(msg.sender == expected);
    }

    /// Pure functions do NOT receive msg_sender.
    function pureAdd(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 c = a + b;
        assert(c == a + b);
        return c;
    }
}
