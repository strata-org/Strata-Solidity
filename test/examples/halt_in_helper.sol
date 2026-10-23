// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Assembly `return` ends the whole transaction, also inside an internal
// function: on that path `stopInHelper(7)` succeeds with x == 1. The halt
// was modelled as a return to the caller, which then ran `x = 2`, so the
// wrong postcondition below was proven. A call of a function that may halt
// is now rejected. (A halt in the entry point itself is still modelled: see
// assembly_havoc.sol.)
contract HaltInHelper {
    uint256 public x;

    function _maybeStop(uint256 v) internal pure {
        assembly { if eq(v, 7) { return(0, 0) } }
    }

    // Wrong: x is 1 when v == 7.
    /// @custom:strata ensures x == 2
    function stopInHelper(uint256 v) external {
        x = 1;
        _maybeStop(v);
        x = 2;
    }
}
