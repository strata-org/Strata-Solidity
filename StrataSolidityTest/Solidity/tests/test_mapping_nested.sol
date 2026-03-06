// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// Nested mapping: mapping(address => mapping(address => uint256)).
contract MappingNested {
    mapping(address => mapping(address => uint256)) public allowances;

    function approve(address spender, uint256 amount) public {
        allowances[msg.sender][spender] = amount;
        assert(allowances[msg.sender][spender] == amount);
    }
}
