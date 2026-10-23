// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Rejected: `super.f(…)` (or `Base.f(…)`) where `f` is overloaded stops
// the translation of the whole file: the call is not resolved to one of
// the overloads. Gap `super-overloaded` in docs/capabilities.toml.
contract Base {
    uint256 public x;

    function set(uint256 v) public virtual {
        x = v;
    }

    function set(uint256 v, uint256 w) public virtual {
        x = v + w;
    }
}

contract Derived is Base {
    /// @custom:strata ensures x == v
    function set(uint256 v) public override {
        super.set(v);
    }
}
