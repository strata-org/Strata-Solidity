// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ReentrancyVulnerable — Vault with a classic reentrancy bug
/// @notice The withdraw function updates state AFTER the external call,
///         so the ensures postcondition may fail under reentrant execution.
contract ReentrancyVulnerable {
    mapping(address => uint256) public balances;

    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) + msg.value
    /// @custom:strata modifies balances
    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @custom:strata requires balances[msg.sender] >= amount
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    /// @custom:strata modifies balances
    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "insufficient balance");
        // BUG: state update AFTER external call — reentrancy possible
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
        balances[msg.sender] -= amount; // too late!
    }
}
