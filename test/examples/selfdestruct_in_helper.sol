// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// `selfdestruct` ends the whole transaction, also inside an internal
// function: on that path `kill(7)` succeeds with x == 1. It was modelled as
// a return to the caller, which then ran `x = 2`, so the wrong
// postcondition below was proven. A call of a function that may halt is
// now rejected. (A `selfdestruct` in the entry point itself is still
// modelled: see unknown_values.sol.)
contract SelfdestructInHelper {
    uint256 public x;

    function _maybeKill(uint256 v) internal {
        if (v == 7) selfdestruct(payable(msg.sender));
    }

    // Wrong: x is 1 when v == 7.
    /// @custom:strata ensures x == 2
    function kill(uint256 v) external {
        x = 1;
        _maybeKill(v);
        x = 2;
    }
}
