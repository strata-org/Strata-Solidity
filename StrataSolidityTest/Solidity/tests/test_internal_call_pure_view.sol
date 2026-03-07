// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: View function calling a pure function with a state variable argument.
/// The require ensures the precondition of double() is satisfied.
contract PureAndView {
    uint256 public stored;

    function double(uint256 x) public pure returns (uint256) {
        return x + x;
    }

    function getDoubleStored() external view returns (uint256 result) {
        uint256 s = stored;
        require(s >= 0);
        result = double(s);
    }
}
