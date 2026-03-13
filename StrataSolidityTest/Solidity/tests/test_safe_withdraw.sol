// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title SafeWithdraw — specification-based verification.
/// Uses _strata_post postconditions for most functions; transferTo retains
/// inline assert() to test mixed specification styles.
contract SafeWithdraw {

    /// Deposit: adds `amount` to a user balance, returns new balance.
    /// @custom:strata ensures newBalance == balance + amount
    function deposit(uint256 balance, uint256 amount) public pure returns (uint256 newBalance) {

        require(balance <= 10000, "balance too large");
        require(amount <= 10000, "amount too large");
        newBalance = balance + amount;
    }

    /// Withdraw: the classic checks-effects pattern.
    /// @custom:strata ensures newBalance + amount == balance
    function withdraw(uint256 balance, uint256 amount) public pure returns (uint256 newBalance) {

        require(amount <= balance, "insufficient funds");
        newBalance = balance - amount;
    }

    /// Verify transfer conserves total supply (sender side).
    /// @custom:strata ensures newFrom + amount == fromBal
    function transferFrom(uint256 fromBal, uint256 amount) public pure returns (uint256 newFrom) {

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
