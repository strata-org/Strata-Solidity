// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A base constructor runs as part of the derived contract's deployment.
// That is not modelled yet, so a contract whose base has a constructor
// that does something is rejected (an empty one is fine).

contract Owned {
    address public owner;

    constructor() {
        owner = msg.sender;
    }
}

contract Vault is Owned {
    uint256 public total;
}
