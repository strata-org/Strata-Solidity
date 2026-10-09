// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Without an explicit constructor, the zero-initialized deployment state
// must satisfy the invariants (checked by an implicit constructor).
// Otherwise every function would assume invariants that nothing
// establishes, and an unsatisfiable one would make everything pass.

// Holds at deployment: verified.
contract ZeroHolds {
    /// @custom:strata invariant x <= 10
    uint256 public x;

    function setSmall(uint256 v) public {
        require(v <= 10);
        x = v;
    }
}

// Fails at deployment (x == 0): the implicit constructor's check fails.
contract ZeroViolates {
    /// @custom:strata invariant x >= 1
    uint256 public x;

    function poke() public {
        assert(x != 0);
        x = x + 1;
    }
}

// Unsatisfiable: the implicit constructor's check fails, which is the
// only way to notice that every function now verifies vacuously.
contract Contradictory {
    /// @custom:strata invariant x > 10
    /// @custom:strata invariant x < 5
    uint256 public x;

    function boom() public {
        assert(false);
    }
}

// An abstract contract is checked the same way, as the initial state of
// the contracts that derive from it: the check fails (x == 0).
abstract contract AbstractBase {
    /// @custom:strata invariant x >= 1
    uint256 public x;

    function poke() public {
        x = x + 1;
    }
}

// The constructor is not verified (it uses a struct-valued mapping), so it
// establishes nothing: the invariants are not assumed, and a warning says
// they are not verified. `assert(false)` is refuted.
contract SkippedConstructor {
    struct Payment { uint256 amount; }
    mapping(address => Payment) public payments;

    /// @custom:strata invariant x > 10
    /// @custom:strata invariant x < 5
    uint256 public x;

    constructor() {
        payments[msg.sender].amount = 1;
    }

    function boom() public {
        assert(false);
    }
}
