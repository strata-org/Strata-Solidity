// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract StructOnly {
    struct Token {
        address owner;
        uint256 amount;
        bool active;
    }
}
