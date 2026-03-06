// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// Basic dynamic array: declares uint[] state variable,
/// uses .length and .push() in functions.
contract ArrayBasic {
    uint[] public values;

    function getLength() public view returns (uint) {
        return values.length;
    }

    function addValue(uint v) public {
        values.push(v);
    }
}
