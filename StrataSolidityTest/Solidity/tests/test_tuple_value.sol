// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A tuple used as a value is not supported. It used to become
// `assume false`, which made the false `ensures` below verify; it must
// now fail translation instead.
contract TupleValue {
    /// @custom:strata ensures a == 12345
    function two() external pure returns (uint256 a, uint256 b) {
        return (1, 2);
    }
}
