// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Events {
    event Transfer(address indexed from, address indexed to, uint256 value);

    mapping(address => uint256) public balances;

    function transfer(address to, uint256 amount) public {
        require(balances[msg.sender] >= amount);
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
    }
}
