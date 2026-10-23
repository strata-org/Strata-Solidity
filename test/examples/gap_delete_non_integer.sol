// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: `delete` of a value that is not an integer or an address
// (a `bool`, here; also an array or a struct) stops the translation of the
// whole file. Gap `delete-non-integer` in docs/capabilities.toml.
contract GapDeleteNonInteger {
    bool public paused;

    /// @custom:strata ensures !paused
    function unpause() external {
        delete paused;
    }
}
