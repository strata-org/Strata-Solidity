// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Rejected: the specification language has no `**`, bitwise or shift
// operators, so a spec using one stops the translation of the whole file
// ("Unexpected tokens after spec expression"). Gap `spec-operators` in
// docs/capabilities.toml.
contract GapSpecOperators {
    /// @custom:strata ensures r == a & 1
    function lowBit(uint256 a) external pure returns (uint256 r) {
        r = a & 1;
    }
}
