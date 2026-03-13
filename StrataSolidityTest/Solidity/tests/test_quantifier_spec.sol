// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Quantifier tests for forall/exists in NatSpec specs.
contract QuantifierSpec {

    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    /// @custom:strata ensures forall a : address :: balances[a] >= 0
    function mint(address to, uint256 amount) external {
        require(amount <= 10000, "amount too large");
        totalSupply += amount;
        balances[to] += amount;
    }
}
