// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// `super.f()` runs the implementation of `f` inherited from the contract
// that follows the one the call is written in. A single chain has one
// linearization (Top, Mid, Base), so each postcondition describes the same
// behavior wherever its contract is verified, and the whole chain is
// proven: `Top.setX` adds nothing, `Mid.setX` adds 2, `Base.setX` adds 1.

contract Base {
    uint256 public x;

    /// @custom:strata ensures x == val + 1
    function setX(uint256 val) public virtual {
        x = val + 1;
    }
}

contract Mid is Base {
    /// @custom:strata ensures x == val + 3
    function setX(uint256 val) public virtual override {
        super.setX(val + 2);
    }
}

contract Top is Mid {
    /// @custom:strata ensures x == val + 3
    /// @custom:strata ensures x > val
    function setX(uint256 val) public override {
        super.setX(val);
    }
}
