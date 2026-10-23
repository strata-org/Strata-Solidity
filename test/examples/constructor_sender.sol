// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// In a constructor, `msg.sender` is the deployer: a value of type
// `address`, not the zero address, and the same at every read.
contract ConstructorSender {
    /// @custom:strata invariant owner != address(0)
    address public owner;
    address public admin;

    // Passes: the deployer is stored, and is not the zero address (the
    // invariant above, checked after the constructor).
    /// @custom:strata ensures owner == msg.sender
    /// @custom:strata ensures admin == owner
    constructor() {
        owner = msg.sender;
        admin = msg.sender;
    }
}

contract ConstructorSenderWrong {
    address public owner;

    // Refuted: the stored address is the deployer's.
    /// @custom:strata ensures owner != msg.sender
    constructor() {
        owner = msg.sender;
    }
}
