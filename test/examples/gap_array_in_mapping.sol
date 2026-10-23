// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: `push` on an array that is not itself a state variable
// (an array in a mapping, here) stops the translation of the whole file.
// Gap `array-push-nested` in docs/capabilities.toml.
contract GapArrayInMapping {
    mapping(address => uint256[]) public lists;
    uint256 public x;

    /// @custom:strata ensures x == 1
    function add(uint256 v) external {
        x = 1;
        lists[msg.sender].push(v);
    }
}
