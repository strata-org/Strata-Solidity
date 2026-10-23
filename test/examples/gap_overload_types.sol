// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: overloads whose parameters differ only between integer
// and address types (`set(uint256)` and `set(address)`) stop the
// translation of the whole file: both kinds are integers in the
// translation, so the two functions get the same signature. Overloads with
// a different number of parameters work. Gap `overload-types` in
// docs/capabilities.toml.
contract GapOverloadTypes {
    uint256 public x;

    /// @custom:strata ensures x == v
    function set(uint256 v) external {
        x = v;
    }

    /// @custom:strata ensures x == 7
    function set(address) external {
        x = 7;
    }
}
