// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Forall quantifier over mapping values.
contract ForallMapping {

    mapping(address => uint256) public balances;

    /// @custom:strata ensures forall a : address :: balances[a] >= 0
    function deposit(address to, uint256 amount) external {
        require(amount <= 10000);
        balances[to] += amount;
    }
}
