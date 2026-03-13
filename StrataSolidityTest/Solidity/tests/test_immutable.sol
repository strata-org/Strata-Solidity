// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Immutable state variable set in constructor.
contract WithImmutable {
    uint256 public immutable THRESHOLD;

    constructor(uint256 t) {
        THRESHOLD = t;
    }

    function check(uint256 x) public view returns (uint256) {
        require(x >= THRESHOLD);
        assert(x >= THRESHOLD);
        return x;
    }
}
