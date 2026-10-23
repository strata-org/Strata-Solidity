// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A base contract in another file. Only the verified source unit's
// contracts are flattened into their derived contracts, so what this
// declares is reported as not part of the verification.
/// @custom:strata invariant owner != address(0)
contract Ownable {
    address public owner;

    constructor() {
        owner = msg.sender;
    }
}
