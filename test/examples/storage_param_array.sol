// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// An array `storage` parameter refers to the caller's storage: `_set0(arr)`
// writes `arr[0]`. It was modelled as a local copy, so the write was lost.
// The file is now rejected.
contract StorageParamArray {
    uint256[] public arr;

    function _set0(uint256[] storage a) internal {
        a[0] = 5;
    }

    // Wrong: arr[0] becomes 5.
    /// @custom:strata requires arr.length > 0 && arr[0] == 1
    /// @custom:strata ensures arr[0] == 1
    function set() external {
        _set0(arr);
    }

    // Holds.
    /// @custom:strata requires arr.length > 0
    /// @custom:strata ensures arr[0] == 5
    function setTrue() external {
        _set0(arr);
    }
}
