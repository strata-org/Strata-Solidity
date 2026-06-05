// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

type Wei is uint256;

// Exercises UserDefinedValueTypeDefinition through the real verification
// harness. Wei.wrap/Wei.unwrap are modeled as identity on the underlying
// uint256, and UDVT-typed locals resolve to TInt. Regression guard for #13.
contract ModernTypes {
    mapping(address account => Wei balance) public deposits;

    /// @custom:strata ensures r == raw
    function roundTrip(uint256 raw) external pure returns (uint256 r) {
        Wei w = Wei.wrap(raw);
        r = Wei.unwrap(w);
    }
}
