// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: using-for directive is silently skipped.
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "overflow");
        return c;
    }
}

contract TestUsingFor {
    using SafeMath for uint256;

    function safeAdd(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 result = a + b;
        require(result >= a, "overflow");
        assert(result >= a);
        return result;
    }
}
