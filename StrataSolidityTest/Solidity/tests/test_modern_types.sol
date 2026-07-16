// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

type Wei is uint256;

// Exercises modern type-system features that translate end-to-end:
//  - UserDefinedValueTypeDefinition (UDVT) with wrap/unwrap as identity in
//    function bodies
//  - named mapping parameters (mapping(address account => Wei balance))
// UDVT in @custom:strata specs is a separate spec-parser concern, not covered.
contract ModernTypes {
    mapping(address account => Wei balance) public deposits;

    /// @custom:strata ensures r == raw
    function roundTrip(uint256 raw) external pure returns (uint256 r) {
        Wei w = Wei.wrap(raw);
        r = Wei.unwrap(w);
    }
}
