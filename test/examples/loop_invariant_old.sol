// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// In a loop invariant, `old(e)` is the value of `e` when the function was
// entered, as in `ensures`: not its value when the loop was entered. Here
// `x` changes before the loop, so the two readings differ.
contract LoopInvariantOld {
    uint256 public x;

    // Passes: counted from the function's entry, the loop adds `i` to the
    // 5 added before it.
    /// @custom:strata requires n <= 100
    /// @custom:strata requires x <= 1000
    /// @custom:strata loop-invariant y == old(x) + 5 + i
    /// @custom:strata loop-invariant i <= n
    /// @custom:strata ensures x == old(x) + 5 + n
    function fromEntry(uint256 n) external {
        x = x + 5;
        uint256 y = x;
        for (uint256 i = 0; i < n; i++) {
            y = y + 1;
        }
        x = y;
    }

    // Refuted: this reads `old(x)` as the value at the loop's entry, which
    // it is not, so the invariant does not hold when the loop starts.
    /// @custom:strata requires n <= 100
    /// @custom:strata requires x <= 1000
    /// @custom:strata loop-invariant y == old(x) + i
    /// @custom:strata loop-invariant i <= n
    function fromLoopEntry(uint256 n) external {
        x = x + 5;
        uint256 y = x;
        for (uint256 i = 0; i < n; i++) {
            y = y + 1;
        }
        x = y;
    }

    // Not proven: the same loop, writing `x` itself. Its invariants and the
    // postcondition are proven, but the function's `heap frame` obligation
    // is unknown: the loop does not keep the fact that only this
    // contract's state changes.
    /// @custom:strata requires n <= 100
    /// @custom:strata requires x <= 1000
    /// @custom:strata loop-invariant x == old(x) + 5 + i
    /// @custom:strata loop-invariant i <= n
    /// @custom:strata ensures x == old(x) + 5 + n
    function inState(uint256 n) external {
        x = x + 5;
        for (uint256 i = 0; i < n; i++) {
            x = x + 1;
        }
    }
}
