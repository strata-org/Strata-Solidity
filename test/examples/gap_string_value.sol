// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: `string` and `bytes` values (a local, `.length`, a
// conversion such as `bytes(s)`) stop the translation of the whole file;
// a `string` parameter that is only passed on (to an event, here) works.
// Gap `string-bytes` in docs/capabilities.toml.
contract GapStringValue {
    /// @custom:strata ensures r == 5
    function len() external pure returns (uint256 r) {
        string memory s = "hello";
        r = bytes(s).length;
    }
}
