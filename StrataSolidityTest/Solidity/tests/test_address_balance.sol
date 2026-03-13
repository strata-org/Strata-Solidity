// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: address(x).balance and address(this).balance translation.
contract AddressBalanceTest {
    function checkBalance(address user) public view returns (uint256) {
        return address(user).balance;
    }

    function checkThisBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
