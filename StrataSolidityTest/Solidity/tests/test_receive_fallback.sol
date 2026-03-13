// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ReceiveFallback {
    uint256 public totalReceived;

    receive() external payable {
        totalReceived += msg.value;
    }

    fallback() external payable {
        totalReceived += 1;
    }

    function getTotal() public view returns (uint256) {
        return totalReceived;
    }
}
