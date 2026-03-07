// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// Contract with mapping state variable AND a pure helper function.
/// Tests that pure functions don't get mapping _in parameters or init-assigns.
contract MappingPureHelper {
    mapping(address => uint256) public balances;

    function add(uint256 a, uint256 b) public pure returns (uint256) {
        assert(a + b >= a);
        return a + b;
    }
}
