// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ReturnValues {
    function identity(uint256 x) public pure returns (uint256) {
        return x;
    }

    function conditional_return(uint256 x) public pure returns (uint256) {
        if (x > 10) {
            return x;
        }
        return 10;
    }

    function early_return(uint256 x) public pure returns (uint256) {
        if (x == 0) {
            return 0;
        }
        uint256 y = x + 1;
        assert(y > x);
        return y;
    }
}
