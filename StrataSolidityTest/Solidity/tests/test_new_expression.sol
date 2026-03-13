// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Tests new-expression contract creation.

contract Token {
    uint256 public supply;
    constructor(uint256 _supply) {
        supply = _supply;
    }
}

contract Factory {
    function create(uint256 amount) external returns (Token) {
        Token t = new Token(amount);
        return t;
    }
}
