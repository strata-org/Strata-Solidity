// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Reentrancy mutex pattern with NatSpec verification specs.
/// @custom:strata invariant locked == false
contract ReentrancyMutex {

    bool private locked;
    mapping(address => uint256) public balances;

    modifier noReentrant() {
        require(!locked, "reentrant call");
        locked = true;
        _;
        locked = false;
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @custom:strata requires balances[msg.sender] >= amount
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    function withdraw(uint256 amount) public noReentrant {
        require(balances[msg.sender] >= amount, "insufficient balance");
        balances[msg.sender] -= amount;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
    }
}
