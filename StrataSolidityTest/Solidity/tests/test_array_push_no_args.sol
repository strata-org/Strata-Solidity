// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// Test: arr.push() with no arguments (valid Solidity ≥0.6.0).
/// Expected: unsupported error (not a type error).
contract ArrayPushNoArgs {
    uint[] public values;

    function addDefault() public {
        values.push();
    }
}
