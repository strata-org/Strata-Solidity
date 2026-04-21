// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Bench 4: Conditionals, multiple paths, fee math
contract B4_Vault {
    mapping(address => uint256) public deposits;
    uint256 public totalDeposits;
    address public owner;
    uint256 public feeBps;

    /// @custom:strata requires msg.value > 0
    /// @custom:strata ensures deposits[msg.sender] == old(deposits[msg.sender]) + msg.value
    /// @custom:strata ensures totalDeposits == old(totalDeposits) + msg.value
    function deposit() external payable {
        require(msg.value > 0, "zero");
        deposits[msg.sender] += msg.value;
        totalDeposits += msg.value;
    }

    /// @custom:strata requires amount > 0
    /// @custom:strata requires amount <= deposits[msg.sender]
    /// @custom:strata ensures deposits[msg.sender] == old(deposits[msg.sender]) - amount
    /// @custom:strata ensures totalDeposits == old(totalDeposits) - amount
    function withdraw(uint256 amount) external {
        require(amount > 0, "zero");
        require(amount <= deposits[msg.sender], "insufficient");
        deposits[msg.sender] -= amount;
        totalDeposits -= amount;
    }

    /// @custom:strata requires msg.sender == owner
    /// @custom:strata requires newFee <= 1000
    /// @custom:strata ensures feeBps == newFee
    function setFee(uint256 newFee) external {
        require(msg.sender == owner, "not owner");
        require(newFee <= 1000, "max 10%");
        feeBps = newFee;
    }
}
