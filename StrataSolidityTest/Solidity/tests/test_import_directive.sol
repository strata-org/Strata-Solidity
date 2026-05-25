// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./helpers/MathLib.sol";

contract ImportTest {
    using MathLib for uint256;

    function addValues(uint256 a, uint256 b) external pure returns (uint256) {
        return MathLib.add(a, b);
    }
}
