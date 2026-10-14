// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// `super` follows the C3 linearization, which depends on the contract being
// verified: for `D is B, C` the order is D, C, B, A, so `C.setX`'s `super`
// is `B.setX` here, while it is `A.setX` when C is verified on its own.
//
// An absolute postcondition cannot hold in both linearizations: `C.setX`
// adds 2 to what its `super` produces, which is `val + 1` inside D and
// `val` in C alone. The specification below is the one D needs, so
// `D.setX`'s chain is proven, and the same clause is reported `unknown`
// for C on its own — where it does not hold.

contract A {
    uint256 public x;

    /// @custom:strata ensures x == val
    function setX(uint256 val) public virtual {
        x = val;
    }
}

contract B is A {
    /// @custom:strata ensures x == val + 1
    function setX(uint256 val) public virtual override {
        super.setX(val + 1);
    }
}

contract C is A {
    /// @custom:strata ensures x == val + 3
    function setX(uint256 val) public virtual override {
        super.setX(val + 2);
    }
}

contract D is B, C {
    /// @custom:strata ensures x == val + 3
    function setX(uint256 val) public override(B, C) {
        super.setX(val);
    }
}
