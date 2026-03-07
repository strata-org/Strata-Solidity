// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: View function calls a pure function whose parameter shadows a state variable.
/// Exercises the interaction between shadowing and pure/non-pure call distinction.
contract ShadowPureView {
    uint256 public x;

    function double(uint256 x) public pure returns (uint256) {
        // x here is the parameter, not the state variable
        return x + x;
    }

    function getDoubleX() external view returns (uint256 result) {
        uint256 val = x;  // reads state variable
        require(val >= 0);
        result = double(val);
    }
}
