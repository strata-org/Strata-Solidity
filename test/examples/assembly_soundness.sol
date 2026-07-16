// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Regression guard for the inline-assembly soundness fix. Before the fix,
// InlineAssembly fell through to assume(false) and ANY post-assembly spec
// passed vacuously. The havoc strategy now treats assembly-touched state as
// unknown, so a spec that does NOT depend on assembly-modified state still
// verifies, exercising the havoc without going vacuous.
contract AssemblySoundness {
    uint256 public stored;

    /// @custom:strata ensures y == x
    function passthrough(uint256 x) external returns (uint256 y) {
        y = x;
        assembly {
            // Touches storage; havoc'd afterward. Does not affect local `y`.
            sstore(stored.slot, x)
        }
    }
}
