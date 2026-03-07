// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title old() on mapping state variables.
/// Tests that _strata_old correctly references pre-state mapping values.
contract OldMapping {

    function _strata_pre(bool) internal pure {}
    function _strata_post(bool) internal pure {}
    function _strata_old_uint(uint256) internal pure returns (uint256) { return 0; }

    mapping(address => uint256) public balances;

    /// After adding `amount`, the new balance equals old balance + amount.
    function deposit(address to, uint256 amount) external {
        _strata_pre(balances[to] <= 100000);
        _strata_post(balances[to] == _strata_old_uint(balances[to]) + amount);

        require(amount <= 10000, "amount too large");
        balances[to] += amount;
    }
}
