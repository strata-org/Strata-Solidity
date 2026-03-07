// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// Basic mapping: mapping(address => uint256) state variable with read/write.
contract MappingBasic {
    mapping(address => uint256) public balances;

    function deposit(uint256 amount) public {
        require(balances[msg.sender] >= 0);
        balances[msg.sender] += amount;
        assert(balances[msg.sender] >= amount);
    }
}
