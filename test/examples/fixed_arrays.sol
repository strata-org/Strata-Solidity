// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A fixed-size array (`uint256[N]`) always has its declared length; a
// dynamic one starts empty. The invariant is false at deployment (the
// length is 3), so it must not pass.
/// @custom:strata invariant slots.length == 0
contract FixedArrays {
    uint256 constant N = 3;
    uint256[N] public slots;
    uint256[] public items;

    /// @custom:strata ensures r == 3
    function slotCount() external view returns (uint256 r) {
        r = slots.length;
    }

    /// @custom:strata ensures items.length == old(items.length) + 1
    function add(uint256 v) external {
        items.push(v);
    }
}
