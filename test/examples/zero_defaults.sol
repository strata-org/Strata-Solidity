// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Return variables and locals declared without a value start at their
// type's zero value, as in Solidity.
contract ZeroDefaults {
    // Passes: a return variable that is never assigned is zero.
    /// @custom:strata ensures r == 0
    function neverAssigned() external pure returns (uint256 r) {}

    // Passes: assigned on one path only.
    /// @custom:strata ensures x > 10 || r == 0
    function onePath(uint256 x) external pure returns (uint256 r) {
        if (x > 10) {
            r = x;
        }
    }

    // Passes: an accumulator declared without a value starts at zero.
    /// @custom:strata ensures r == x
    function accumulate(uint256 x) external pure returns (uint256 r) {
        uint256 acc;
        acc += x;
        r = acc;
    }

    // Passes: a bool starts false.
    /// @custom:strata ensures !r
    function boolStartsFalse() external pure returns (bool r) {
        bool flag;
        r = flag;
    }

    // Fails: x can be anything.
    /// @custom:strata ensures r == 0
    function assigned(uint256 x) external pure returns (uint256 r) {
        r = x;
    }
}

// State starts at zero too, struct fields included.
contract ZeroState {
    struct Info { uint256 value; bool flag; }

    Info internal info;
    uint256 public count;

    // Passes: the constructor starts from zeroed state.
    /// @custom:strata ensures count == 1
    /// @custom:strata ensures info.value == 0 && !info.flag
    constructor() {
        count = 1;
    }
}
