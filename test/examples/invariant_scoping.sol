// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Invariants are about contract state. A parameter that shadows a state
// variable must not capture the invariant, named constants fold in every
// function including the constructor, and `items.length` refers to the
// pre-state length in the invariant's precondition.
contract InvariantScoping {
    uint256 public constant MAX = 100;

    /// @custom:strata invariant cap >= 1
    uint256 public cap;

    /// @custom:strata invariant x <= MAX
    uint256 public x;

    /// @custom:strata invariant items.length <= MAX
    uint256[] public items;

    uint256 public other;

    constructor() {
        cap = 1;
        x = 5;
    }

    function setX(uint256 v) public {
        require(v <= MAX);
        x = v;
    }

    // The parameter `cap` shadows the state variable; the invariant still
    // constrains the state, so nothing is known about the argument and the
    // assertion is refuted (cap = 0).
    function setOther(uint256 cap) public {
        assert(cap != 0);
        other = cap;
    }
}
