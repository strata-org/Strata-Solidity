// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// `push` on a dynamic storage array adds one element at the end: the
// length grows by one, the new last element is the pushed value, and the
// earlier elements are unchanged. (`pop` is not supported: see
// gap_array_pop.sol.)
contract DynamicArrays {
    uint256[] public items;

    // Passes: the length and the stored value.
    /// @custom:strata ensures items.length == old(items.length) + 1
    /// @custom:strata ensures items[old(items.length)] == v
    function add(uint256 v) external {
        items.push(v);
    }

    // Passes: an earlier element is unchanged.
    /// @custom:strata requires i < items.length
    /// @custom:strata ensures items[i] == old(items[i])
    function addKeeps(uint256 i, uint256 v) external {
        items.push(v);
    }

    // Refuted: one push adds one element.
    /// @custom:strata ensures items.length == old(items.length) + 2
    function addWrongLength(uint256 v) external {
        items.push(v);
    }

    // Refuted: the pushed value is at the old length, not at index 0.
    /// @custom:strata ensures items[0] == v
    function addWrongIndex(uint256 v) external {
        items.push(v);
    }
}
