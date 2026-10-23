// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Rejected: `**` with an operand that is not a constant stops the
// translation of the whole file; a power of constants (`2 ** 64`) is
// folded. Gap `power-variable` in docs/capabilities.toml.
contract GapPowerVariable {
    /// @custom:strata ensures r == 8
    function cube() external pure returns (uint256 r) {
        uint256 b = 2;
        r = b ** 3;
    }
}
