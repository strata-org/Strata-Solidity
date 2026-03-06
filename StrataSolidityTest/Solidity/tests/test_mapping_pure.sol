// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// View function taking a mapping-typed state variable.
/// Tests that mapping(uint256 => uint256) parses and translates.
contract MappingPure {
    mapping(uint256 => uint256) public data;

    function lookup(uint256 key) public view returns (uint256) {
        return data[key];
    }
}
