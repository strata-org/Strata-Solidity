// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: the `.length` of a memory array created with `new`
// stops the translation of the whole file. Gap `new-array-length` in
// docs/capabilities.toml.
contract GapNewArrayLength {
    /// @custom:strata ensures r == n
    function make(uint256 n) external pure returns (uint256 r) {
        uint256[] memory a = new uint256[](n);
        r = a.length;
    }
}
