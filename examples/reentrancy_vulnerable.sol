// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ReentrancyVulnerable
/// @notice Withdraw with state update after external call — may FAIL verification.
contract ReentrancyVulnerable {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient");
        // External call before state update — reentrancy risk
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        balances[msg.sender] -= amount;
    }
}
