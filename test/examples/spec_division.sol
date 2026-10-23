// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// In a specification, `/` and `%` divide as in Solidity: `/` rounds toward
// zero and `%` takes the sign of the dividend (`-7 / 2 == -3`,
// `-7 % 2 == -1`). They used to be Euclidean (`-7 % 2 == 1`), so
// `a % 2 == 0 || a % 2 == 1` was proven for every int256 `a`.
contract SpecDivision {
    // Passes: a spec divides like the code, rounding toward zero.
    /// @custom:strata ensures r == a / 2
    function half(int256 a) external pure returns (int256 r) {
        r = a / 2;
    }

    // Refuted: `>>` rounds down, so -7 >> 1 is -4, not -7 / 2 == -3.
    /// @custom:strata ensures r == a / 2
    function halfByShift(int256 a) external pure returns (int256 r) {
        r = a >> 1;
    }

    // Passes: a spec's remainder is the code's.
    /// @custom:strata ensures r == a % 2
    function remainder(int256 a) external pure returns (int256 r) {
        r = a % 2;
    }

    // Refuted: -7 % 2 is -1.
    /// @custom:strata ensures a % 2 == 0 || a % 2 == 1
    function parity(int256 a) external pure returns (int256 r) {
        r = a % 2;
    }
}
