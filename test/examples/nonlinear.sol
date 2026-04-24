// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract NonLinear {
    uint256 public x;
    uint256 public y;

    // Linear
    /// @custom:strata modifies x
    /// @custom:strata ensures x == old(x) + amount
    function add(uint256 amount) external {
        x += amount;
    }

    // Constant multiply
    /// @custom:strata modifies x
    /// @custom:strata ensures x == old(x) * 2
    function doubleX() external {
        x = x * 2;
    }

    // Variable * variable
    /// @custom:strata requires a > 0
    /// @custom:strata requires b > 0
    /// @custom:strata modifies x
    /// @custom:strata ensures x == a * b
    function setProduct(uint256 a, uint256 b) external {
        x = a * b;
    }

    // Division rounding: (a*b)/c <= a when b <= c
    /// @custom:strata requires b <= c
    /// @custom:strata requires c > 0
    /// @custom:strata modifies x
    /// @custom:strata ensures x <= a
    function divRound(uint256 a, uint256 b, uint256 c) external {
        require(b <= c && c > 0);
        x = (a * b) / c;
    }

    // Compound interest: x + x*rate/1000 >= x
    /// @custom:strata requires rate <= 1000
    /// @custom:strata modifies x
    /// @custom:strata ensures x >= old(x)
    function accrue(uint256 rate) external {
        require(rate <= 1000);
        x = x + (x * rate) / 1000;
    }

    // Fee calculation: fee = amount * 3 / 1000, fee <= amount
    /// @custom:strata modifies x
    /// @custom:strata ensures x <= amount
    function setFee(uint256 amount) external {
        x = (amount * 3) / 1000;
    }
}
