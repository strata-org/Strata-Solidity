// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Contract with documented struct
contract DocStruct {
    /// @notice A point in 2D space
    struct Point {
        /// @notice x coordinate
        uint256 x;
        /// @notice y coordinate
        uint256 y;
    }

    /// @notice Adds two values
    function add(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}
