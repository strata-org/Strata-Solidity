// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: a type conversion in a specification (`uint8(x)`) stops
// the translation of the whole file; in the function body it works.
// Gap `spec-conversion` in docs/capabilities.toml.
contract GapSpecConversion {
    /// @custom:strata ensures uint8(x) == small
    function low(uint256 x) external pure returns (uint8 small) {
        small = uint8(x);
    }
}
