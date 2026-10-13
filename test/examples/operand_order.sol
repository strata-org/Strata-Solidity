// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// solc's code generators evaluate the operands of a binary operator (and
// the arguments of a call) in different orders, so `_inc() + x`, where
// `_inc` changes `x`, has no single meaning: it is rejected rather than
// verified one way. (Calls that only read state, like `get() + get()`, are
// fine.)
contract OperandOrder {
    uint256 public x;

    /// @custom:strata ensures r == 1
    function _inc() internal returns (uint256 r) {
        x += 1;
        r = 1;
    }

    function both() external returns (uint256) {
        return _inc() + x;
    }
}
