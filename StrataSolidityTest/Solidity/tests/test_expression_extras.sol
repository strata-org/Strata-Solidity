// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Exercises the PR-#15 expression extras that translate end-to-end:
//  - Literal subdenomination (ether/time units) → unit-multiplied value
//  - IndexRangeAccess (calldata slice) → opaque value
// InlineArrayExpression is in the dialect/parser but its translation needs the
// memory-array length-tracking representation (tracked separately); a contract
// using it currently raises a clean "unsupported" error rather than verifying.
contract ExpressionExtras {
    /// @custom:strata ensures r == 1000000000000000000
    function checkEtherUnit() external pure returns (uint256 r) {
        r = 1 ether;
    }

    /// @custom:strata ensures r == 5400
    function checkTimeUnits() external pure returns (uint256 r) {
        r = 1 hours + 30 minutes;
    }

    function sliceExample(bytes calldata data) external pure returns (bytes memory) {
        return data[1:5];
    }
}
