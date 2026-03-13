// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Vault deposit pattern with invariant and ensures.
/// @custom:strata invariant totalDeposits >= 0
contract VaultDeposit {

    mapping(address => uint256) public deposits;
    uint256 public totalDeposits;

    /// @custom:strata requires msg.value <= 100000
    /// @custom:strata ensures deposits[msg.sender] == old(deposits[msg.sender]) + msg.value
    /// @custom:strata ensures totalDeposits == old(totalDeposits) + msg.value
    function deposit() public payable {
        deposits[msg.sender] += msg.value;
        totalDeposits += msg.value;
    }
}
