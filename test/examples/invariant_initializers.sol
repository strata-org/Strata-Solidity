// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// State-variable initializers run before the constructor body, so the
// constructor's invariant check sees them.

contract InitializerEstablishes {
    /// @custom:strata invariant cap == 1000
    uint256 public cap = 1000;

    /// @custom:strata invariant fee <= 100
    uint256 public fee = 50;

    address public owner = msg.sender;

    constructor() {}

    /// @custom:strata ensures fee == newFee
    function setFee(uint256 newFee) public {
        require(newFee <= 100);
        fee = newFee;
    }
}

// The initializer breaks the invariant at deployment: the constructor's
// invariant check must fail.
contract InitializerViolates {
    /// @custom:strata invariant x <= 100
    uint256 public x = 1000;

    constructor() {}
}

// Initializers the translator cannot express (a string, a hash of one,
// `address(this)`) give their variable an unknown value instead of failing
// the file. An inline array literal sets the array's length: the
// constructor's check of `items.length == 0` must fail.
contract InitializerOpaque {
    string public name = "Token";
    bytes32 public tag = keccak256("tag");
    address public self_ = address(this);

    /// @custom:strata invariant items.length == 0
    uint256[] public items = [uint256(1), 2, 3];

    constructor() {}
}
