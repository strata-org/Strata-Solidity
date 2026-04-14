// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Bench 2: Two state variables, arithmetic, two functions
contract B2_Counter {
    uint256 public count;
    uint256 public lastDelta;

    /// @custom:strata requires amount > 0
    /// @custom:strata ensures count == old(count) + amount
    /// @custom:strata ensures lastDelta == amount
    function add(uint256 amount) external {
        require(amount > 0, "zero");
        count += amount;
        lastDelta = amount;
    }

    /// @custom:strata requires amount > 0
    /// @custom:strata requires amount <= count
    /// @custom:strata ensures count == old(count) - amount
    /// @custom:strata ensures lastDelta == amount
    function sub(uint256 amount) external {
        require(amount > 0, "zero");
        require(amount <= count, "underflow");
        count -= amount;
        lastDelta = amount;
    }
}
