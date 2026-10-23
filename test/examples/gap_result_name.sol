// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: a parameter or local variable named `result` in a
// function whose return value is unnamed stops the translation of the
// whole file (the translator names that return value `result`). Gap
// `result-name` in docs/capabilities.toml.
contract GapResultName {
    /// @custom:strata ensures r == a
    function same(uint256 a) external pure returns (uint256 r) {
        r = a;
    }

    function copy(uint256 a) external pure returns (uint256) {
        uint256 result = a;
        return result;
    }
}
