// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title SafeWithdraw — specification-based verification.
/// Uses _strata_post postconditions for most functions; transferTo retains
/// inline assert() to test mixed specification styles.
contract SafeWithdraw {

    // Strata specification stubs
    function _strata_post(bool) internal pure {}

    /// Deposit: adds `amount` to a user balance, returns new balance.
    function deposit(uint256 balance, uint256 amount) public pure returns (uint256 newBalance) {
        _strata_post(newBalance == balance + amount);

        require(balance <= 10000, "balance too large");
        require(amount <= 10000, "amount too large");
        newBalance = balance + amount;
    }

    /// Withdraw: the classic checks-effects pattern.
    function withdraw(uint256 balance, uint256 amount) public pure returns (uint256 newBalance) {
        _strata_post(newBalance + amount == balance);

        require(amount <= balance, "insufficient funds");
        newBalance = balance - amount;
    }

    /// Verify transfer conserves total supply (sender side).
    function transferFrom(uint256 fromBal, uint256 amount) public pure returns (uint256 newFrom) {
        _strata_post(newFrom + amount == fromBal);

        require(amount <= fromBal, "insufficient funds");
        newFrom = fromBal - amount;
    }

    /// Verify transfer conserves total supply (receiver side).
    function transferTo(uint256 toBal, uint256 amount) public pure returns (uint256) {
        require(toBal <= 10000, "balance too large");
        require(amount <= 10000, "amount too large");
        uint256 newTo = toBal + amount;
        assert(newTo == toBal + amount);
        assert(newTo >= toBal);
        return newTo;
    }
}
