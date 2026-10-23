// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: calling a library function (`MathLib.max(a, b)`, or
// `a.max(b)` through `using MathLib for uint256`) stops the translation of
// the whole file. Gap `library-calls` in docs/capabilities.toml.
library MathLib {
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }
}

contract GapLibraryCall {
    /// @custom:strata ensures r >= a && r >= b
    function larger(uint256 a, uint256 b) external pure returns (uint256 r) {
        r = MathLib.max(a, b);
    }
}
