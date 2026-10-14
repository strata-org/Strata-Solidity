// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A contract is verified as the flattening of its bases and itself: what it
// inherits — state, functions, modifiers, invariants, the constructor's
// effect — is part of what is checked, in the derived contract's own
// context. Each contract here is also verified on its own.

contract Owned {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /// @custom:strata ensures r == a + 1
    function _bump(uint256 a) internal pure returns (uint256 r) {
        r = a + 1;
    }
}

/// @custom:strata invariant total <= cap
contract Capped is Owned {
    uint256 public cap = 100;
    uint256 public total;
}

contract Vault is Capped {
    // The inherited state variable resolves, and the inherited invariant
    // `total <= cap` is checked on exit.
    /// @custom:strata requires total + amount <= cap
    /// @custom:strata ensures total == old(total) + amount
    function deposit(uint256 amount) external {
        total = total + amount;
    }

    // The inherited modifier is inlined: its `require` holds in the body.
    /// @custom:strata ensures msg.sender == owner
    function sweep() external onlyOwner {
        total = 0;
    }

    // The inherited internal function is called with its own spec.
    /// @custom:strata requires total < cap
    /// @custom:strata ensures total == old(total) + 1
    function bump() external {
        total = _bump(total);
    }

    // The base constructor ran, so the deployer owns the vault.
    /// @custom:strata ensures r == owner
    function ownerOf() external view returns (address r) {
        r = owner;
    }
}
