// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Contract with a state variable and multiple functions.
/// Verifies that the state variable field is present in the CompositeType
/// and all functions are verified.
contract Counter {
    uint256 public value;

    function addOne(uint256 x) public pure returns (uint256) {
        require(x <= 10000);
        uint256 r1 = x + 1;
        assert(r1 > x);
        return r1;
    }

    function subOne(uint256 x) public pure returns (uint256) {
        require(x > 0);
        uint256 r2 = x - 1;
        assert(r2 < x);
        return r2;
    }
}
