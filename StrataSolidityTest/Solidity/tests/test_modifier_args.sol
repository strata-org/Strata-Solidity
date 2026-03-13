// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Modifier with arguments test.
contract ModifierArgs {

    uint256 public balance;

    modifier minAmount(uint256 min) {
        require(msg.value >= min);
        _;
    }

    /// @custom:strata ensures balance == old(balance) + msg.value
    function deposit() public payable minAmount(100) {
        balance += msg.value;
    }
}
