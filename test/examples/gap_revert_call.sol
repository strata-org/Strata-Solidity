// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: `revert("reason")` and `revert()` stop the translation of
// the whole file; `revert CustomError()` and `require(cond, "reason")`
// work. Gap `revert-call` in docs/capabilities.toml.
contract GapRevertCall {
    uint256 public x;

    /// @custom:strata ensures x == v
    function set(uint256 v) external {
        if (v == 0) revert("zero");
        x = v;
    }
}
