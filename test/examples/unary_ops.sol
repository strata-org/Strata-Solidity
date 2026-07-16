// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Exercises the spec-parser unary layer: logical `!` and unary `-`
// (negative integer literals) in @custom:strata expressions.
contract UnaryOps {
    int256 public tick;
    uint256 public n;

    // Unary minus: negative integer literal bounds (tick-range pattern).
    /// @custom:strata requires t >= -887272
    /// @custom:strata requires t <= 887272
    /// @custom:strata modifies tick
    /// @custom:strata ensures tick == t
    function setTick(int256 t) external {
        require(t >= -887272 && t <= 887272, "range");
        tick = t;
    }

    // Logical not on a boolean parameter.
    /// @custom:strata requires !done
    /// @custom:strata modifies n
    /// @custom:strata ensures n == old(n) + 1
    function step(bool done) external {
        require(!done, "done");
        n += 1;
    }
}
