// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Function coexists with state variable; verifies heap parameterization
/// does not break function verification when state variables are present.
contract UseStateVar {
    uint256 public total;

    function add(uint256 a, uint256 b) public pure returns (uint256) {
        require(a <= 1000);
        require(b <= 1000);
        uint256 sum = a + b;
        assert(sum >= a);
        assert(sum >= b);
        return sum;
    }
}
