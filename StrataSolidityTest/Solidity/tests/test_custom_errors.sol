// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract CustomErrors {
    error InsufficientBalance(uint256 available, uint256 required);
    error Unauthorized(address caller);

    mapping(address => uint256) public balances;

    function withdraw(uint256 amount) public {
        require(balances[msg.sender] >= amount, InsufficientBalance(balances[msg.sender], amount));
        balances[msg.sender] -= amount;
    }

    function restrictedWithdraw(uint256 amount, address admin) public {
        if (msg.sender != admin) {
            revert Unauthorized(msg.sender);
        }
        require(balances[msg.sender] >= amount);
        balances[msg.sender] -= amount;
        assert(balances[msg.sender] <= balances[msg.sender] + amount);
    }
}
