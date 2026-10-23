// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A struct-valued mapping is not supported, and a function using it is not
// verified (reported). A derived constructor that runs a base constructor
// using one is not verified either, nor are the invariants it would
// establish; the derived contract's other functions are.

contract Registry {
    struct P {
        uint256 a;
    }
    mapping(uint256 => P) internal ps;

    constructor() {
        ps[1].a = 1;
    }
}

/// @custom:strata invariant m <= 100
contract Child is Registry {
    uint256 public m;

    constructor() {
        m = 1;
    }

    // Passes.
    /// @custom:strata requires v <= 100
    /// @custom:strata ensures m == v
    function set(uint256 v) external {
        m = v;
    }

    // Refuted.
    /// @custom:strata requires v <= 100
    /// @custom:strata ensures m == v + 1
    function setWrong(uint256 v) external {
        m = v;
    }
}
