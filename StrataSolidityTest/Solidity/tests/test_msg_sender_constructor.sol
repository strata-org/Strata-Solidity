// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Constructor with msg.sender and bytes32 parameter.
/// Verifies the interaction of all three features in this change.
contract MsgSenderConstructor {
    constructor(bytes32 name, uint256 val) {
        // msg.sender is available in the constructor (non-pure)
        require(msg.sender != address(0));
        uint256 check = val + 1;
        assert(check > val);
    }

    function verify(address caller) public view {
        require(msg.sender == caller);
        assert(msg.sender == caller);
    }
}
