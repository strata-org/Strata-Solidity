// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Exercises ImportDirective through the real verification harness. The import
// must not shadow this contract's specs (regression: get_ast was returning the
// first source — the imported library — leaving the main contract unchecked).
import "./lib/Math.sol";

contract ImportDirective {
    using Math for uint256;

    uint256 public stored;

    /// @custom:strata ensures stored == x
    function store(uint256 x) external {
        stored = x;
    }
}
