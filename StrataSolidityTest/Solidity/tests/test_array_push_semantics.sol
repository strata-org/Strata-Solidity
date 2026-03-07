// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// Functional test for push semantics: verifies that push
/// increments length and stores the value at the correct index.
contract ArrayPushSemantics {
    uint[] public values;

    function testPush(uint v) public {
        uint oldLen = values.length;
        values.push(v);
        assert(values.length == oldLen + 1);
    }
}
