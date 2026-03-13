// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Tests C3 linearization with diamond inheritance: D is B, C; B is A; C is A.

contract A {
    uint256 public x;

    /// @custom:strata ensures x == val
    function setX(uint256 val) public virtual {
        x = val;
    }
}

contract B is A {
    function setX(uint256 val) public virtual override {
        super.setX(val + 1);
    }
}

contract C is A {
    function setX(uint256 val) public virtual override {
        super.setX(val + 2);
    }
}

contract D is B, C {
    function setX(uint256 val) public override(B, C) {
        super.setX(val);
    }
}
