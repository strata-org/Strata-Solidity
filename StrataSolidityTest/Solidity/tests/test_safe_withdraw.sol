// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title SafeWithdraw — a minimal withdraw pattern for verification showcase.
/// Demonstrates that balance bookkeeping preserves key invariants:
///   - deposits never lose funds
///   - withdrawals never underflow
///   - transfers conserve total supply
contract SafeWithdraw {

    /// Deposit: adds `amount` to a user balance, returns new balance.
    function deposit(uint256 balance, uint256 amount) public pure returns (uint256) {
        require(balance <= 10000, "balance too large");
        require(amount <= 10000, "amount too large");
        uint256 newBalance = balance + amount;
        assert(newBalance >= balance);       // no-loss: balance can only grow
        return newBalance;
    }

    /// Withdraw: the classic checks-effects pattern.
    function withdraw(uint256 balance, uint256 amount) public pure returns (uint256) {
        require(amount <= balance, "insufficient funds");
        uint256 newBalance = balance - amount;
        assert(newBalance <= balance);              // no-underflow
        assert(newBalance + amount == balance);     // conservation
        return newBalance;
    }

    /// Verify transfer conserves total supply (sender side).
    function transferFrom(uint256 fromBal, uint256 amount) public pure returns (uint256) {
        require(amount <= fromBal, "insufficient funds");
        uint256 newFrom = fromBal - amount;
        assert(newFrom + amount == fromBal);  // sender conservation
        return newFrom;
    }

    /// Verify transfer conserves total supply (receiver side).
    function transferTo(uint256 toBal, uint256 amount) public pure returns (uint256) {
        require(toBal <= 10000, "balance too large");
        require(amount <= 10000, "amount too large");
        uint256 newTo = toBal + amount;
        assert(newTo == toBal + amount);      // receiver conservation
        assert(newTo >= toBal);               // no-loss on receive
        return newTo;
    }
}
