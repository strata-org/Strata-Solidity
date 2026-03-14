// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Transient storage reentrancy lock pattern.
contract TransientLock {

    uint256 transient locked;
    mapping(address => uint256) public balances;

    modifier noReentrant() {
        require(locked == 0);
        locked = 1;
        _;
        locked = 0;
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @custom:strata requires balances[msg.sender] >= amount
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    function withdraw(uint256 amount) public noReentrant {
        require(balances[msg.sender] >= amount);
        balances[msg.sender] -= amount;
    }
}
