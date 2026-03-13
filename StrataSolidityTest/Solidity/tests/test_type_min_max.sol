// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: type(T).min and type(T).max constant folding.
contract TypeMinMaxTest {
    function checkUint256Max() public pure returns (uint256) {
        uint256 x = type(uint256).max;
        assert(x > 0);
        return x;
    }

    function checkUint8Max() public pure returns (uint8) {
        uint8 x = type(uint8).max;
        assert(x == 255);
        return x;
    }

    function checkInt256Min() public pure returns (int256) {
        int256 x = type(int256).min;
        assert(x < 0);
        return x;
    }

    function checkUintMin() public pure returns (uint256) {
        uint256 x = type(uint256).min;
        assert(x == 0);
        return x;
    }
}
