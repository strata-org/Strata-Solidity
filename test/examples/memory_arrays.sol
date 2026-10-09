// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Memory arrays are references, which the translation (arrays as values)
// models as follows: an internal function may write the elements of a
// memory array it is passed, which are unknown afterwards; assigning a
// whole array assigns its length too; and making two memory arrays alias
// (`a = b`, `T[] memory a = b`) is rejected (not exercised here: a
// rejection fails the whole file).
contract MemoryArrays {
    uint256[] public items;
    uint256[] public other;

    function _set(uint256[] memory a) internal pure {
        a[0] = 1;
    }

    // Refuted: `_set` writes `b[0]` through the reference.
    function passed(uint256[] memory b) external pure {
        require(b.length > 0);
        require(b[0] == 0);
        _set(b);
        assert(b[0] == 0);
    }

    // Refuted: `items` takes the length of `other`.
    /// @custom:strata ensures items.length == old(items.length)
    function assignWhole() external {
        items = other;
    }

    /// @custom:strata ensures items.length == other.length
    function assignLength() external {
        items = other;
    }
}
