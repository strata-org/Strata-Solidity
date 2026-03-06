// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Constructor translates as a named procedure.
/// The constructor body uses only local variables and parameters,
/// avoiding state-variable heap parameterization (Phase 2).
contract ConstructorTest {
    constructor(uint256 initVal) {
        uint256 local = initVal + 1;
        assert(local > initVal);
    }

    function pureFunc(uint256 x) public pure returns (uint256) {
        assert(x + 1 > x);
        return x + 1;
    }
}
