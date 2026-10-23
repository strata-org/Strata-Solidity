// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A contract is verified as the flattening of its bases and itself: what it
// inherits (state, functions, modifiers, invariants) is checked in its own
// context, and an obligation of an inherited function names the contract it
// is checked in, `(in Fast)`. Each contract is also verified on its own.

/// @custom:strata invariant count <= limit
contract Counter {
    uint256 public limit = 100;
    uint256 public count;
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /// @custom:strata ensures r == a + 1
    function _plusOne(uint256 a) internal pure returns (uint256 r) {
        r = a + 1;
    }

    /// @custom:strata ensures r == 1
    function _step() internal pure virtual returns (uint256 r) {
        r = 1;
    }

    // Refuted in Fast: there `advance` calls Fast's `_step`, which adds 5.
    // (Proven in Counter.)
    /// @custom:strata requires count + 5 <= limit
    /// @custom:strata ensures count == old(count) + 1
    function advance() public {
        count = count + _step();
    }
}

contract Fast is Counter {
    /// @custom:strata ensures r == 5
    function _step() internal pure override returns (uint256 r) {
        r = 5;
    }

    // Passes: the inherited `advance` runs this contract's `_step`.
    /// @custom:strata requires count + 5 <= limit
    /// @custom:strata ensures count == old(count) + 5
    function advanceFast() external {
        count = count + _step();
    }

    // Passes: the inherited modifier's `require` holds in the body.
    /// @custom:strata ensures msg.sender == owner
    function reset() external onlyOwner {
        count = 0;
    }

    // Refuted: the same modifier admits only the owner.
    /// @custom:strata ensures msg.sender != owner
    function resetWrong() external onlyOwner {
        count = 0;
    }

    // Passes: the inherited internal function is called with its spec.
    /// @custom:strata requires count < limit
    /// @custom:strata ensures count == old(count) + 1
    function bump() external {
        count = _plusOne(count);
    }

    // Refuted: `_plusOne` adds one.
    /// @custom:strata requires count < limit
    /// @custom:strata ensures count == old(count)
    function bumpWrong() external {
        count = _plusOne(count);
    }

    // Passes: the inherited invariant `count <= limit` holds on exit.
    function fill() external {
        count = limit;
    }

    // Refuted: this breaks the inherited invariant.
    function overfill() external {
        count = limit + 1;
    }
}

contract Named {
    uint256 public y;

    function id() external virtual returns (uint256) {
        y = 1;
        return 1;
    }
}

// Passes: in Renamed, `id` is the getter of the state variable that
// overrides the function, so `y` never changes.
/// @custom:strata invariant y == 0
contract Renamed is Named {
    uint256 public override id = 7;
}
