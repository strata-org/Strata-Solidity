// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ForallTest {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    /// @custom:strata ensures forall addr : address :: addr != msg.sender ==> balances[addr] == old(balances[addr])
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) + msg.value
    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }
}
