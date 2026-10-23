// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: a function declared outside a contract is not verified
// (reported), and calling one stops the translation of the whole file.
// Gap `file-level-functions` in docs/capabilities.toml.
function twice(uint256 a) pure returns (uint256) {
    return a * 2;
}

contract GapFileLevelFunction {
    uint256 public x;

    /// @custom:strata ensures x == 4
    function set() external {
        x = twice(2);
    }
}
