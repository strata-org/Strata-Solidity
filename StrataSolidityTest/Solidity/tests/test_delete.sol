// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: delete operator resets variables to default values.
contract DeleteTest {
    uint256 public value;
    mapping(address => uint256) public balances;

    function resetValue() public {
        value = 42;
        delete value;
        assert(value == 0);
    }

    function resetMapping(address a) public {
        balances[a] = 100;
        delete balances[a];
        assert(balances[a] == 0);
    }
}
