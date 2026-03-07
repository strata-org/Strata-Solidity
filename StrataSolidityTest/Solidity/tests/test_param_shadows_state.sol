// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Function parameter shadows a state variable of the same name.
/// The function should use the parameter value, not the state variable.
contract ParamShadow {
    uint256 public x;

    function f(uint256 x) public pure returns (uint256) {
        // x here refers to the parameter, not the state variable
        assert(x == x);  // trivially true for the parameter
        return x;
    }
}
