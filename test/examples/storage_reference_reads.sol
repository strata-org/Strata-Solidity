// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A storage reference (`Info storage d = data;`) refers to the storage of
// `data`: a read `d.value` sees every write to it, also those after the
// reference was taken. Reads used to return the values `data` had when `d`
// was declared, so both wrong postconditions below were proven.
contract StorageReferenceReads {
    struct Info {
        uint256 value;
        bool flag;
    }
    Info public data;

    /// @custom:strata ensures data.value == 5
    function _reset() internal {
        data = Info({value: 5, flag: true});
    }

    // Refuted: `d` reads the struct assigned to `data` after `d` was taken.
    /// @custom:strata requires data.value == 1
    /// @custom:strata ensures r == 1
    function readAfterAssignment() external returns (uint256 r) {
        Info storage d = data;
        data = Info({value: 5, flag: true});
        r = d.value;
    }

    // Passes.
    /// @custom:strata ensures r == 5
    function readAfterAssignmentTrue() external returns (uint256 r) {
        Info storage d = data;
        data = Info({value: 5, flag: true});
        r = d.value;
    }

    // Not proven: `_reset` changes `data`, which `d` reads.
    /// @custom:strata requires data.value == 1
    /// @custom:strata ensures r == 1
    function readAfterCall() external returns (uint256 r) {
        Info storage d = data;
        _reset();
        r = d.value;
    }

    // Passes.
    /// @custom:strata ensures r == 5
    function readAfterCallTrue() external returns (uint256 r) {
        Info storage d = data;
        _reset();
        r = d.value;
    }
}
