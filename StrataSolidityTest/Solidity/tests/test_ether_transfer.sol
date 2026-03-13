// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: transfer, send, and call do not crash the translator.
contract EtherTransferTest {
    function doTransfer(address payable recipient, uint256 amount) public {
        recipient.transfer(amount);
    }

    function doSend(address payable recipient, uint256 amount) public returns (bool) {
        bool success = recipient.send(amount);
        return success;
    }
}
