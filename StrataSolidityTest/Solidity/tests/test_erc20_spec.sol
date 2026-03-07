// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Minimal ERC20-like token with full contract specification.
/// Demonstrates contract invariants, pre/postconditions, and old().
contract ERC20Spec {

    // Strata specification stubs
    // TODO: Extract stubs into a shared Solidity file (e.g., StrataSpec.sol) that
    // tests can import, so stub API changes only need updating in one place.
    function _strata_pre(bool) internal pure {}
    function _strata_post(bool) internal pure {}
    function _strata_old_uint(uint256) internal pure returns (uint256) { return 0; }

    // Contract invariant stub: called in constructor to register the invariant.
    // SolToLaurel intercepts this and conjoins it with every public function's specs.
    function _strata_invariant(bool) internal pure {}

    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    constructor() {
        // Contract invariant: total supply is non-negative
        _strata_invariant(totalSupply >= 0);
    }

    function mint(address to, uint256 amount) external {
        _strata_pre(balances[to] <= 100000);
        _strata_post(totalSupply == _strata_old_uint(totalSupply) + amount);

        require(amount <= 10000, "amount too large");
        require(totalSupply <= 100000, "supply too large");
        totalSupply += amount;
        balances[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        _strata_pre(balances[msg.sender] >= amount);
        _strata_pre(to != msg.sender);
        _strata_post(balances[to] == _strata_old_uint(balances[to]) + amount);
        _strata_post(balances[msg.sender] == _strata_old_uint(balances[msg.sender]) - amount);

        require(to != msg.sender, "self-transfer disallowed");
        require(balances[msg.sender] >= amount, "insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }
}
