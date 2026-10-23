// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: `pop` on a dynamic array stops the translation of the
// whole file. This fixture pins the failure (gap `array-pop` in
// docs/capabilities.toml); when `pop` is modelled, the golden file and
// that entry change together.
contract GapArrayPop {
    uint256[] public items;

    /// @custom:strata ensures items.length == old(items.length) - 1
    function removeLast() external {
        items.pop();
    }
}
