// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title AccessControl — Ownable pattern with a missing zero-address guard
/// @notice The spec is technically satisfied (owner == newOwner after the call),
///         but the contract lacks a require(newOwner != address(0)) check,
///         which is a runtime safety concern rather than a spec violation.
contract AccessControl {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    /// @custom:strata requires msg.sender == owner
    /// @custom:strata ensures owner == newOwner
    /// @custom:strata modifies owner
    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "not owner");
        // Missing: require(newOwner != address(0))
        owner = newOwner;
    }

    /// @custom:strata requires msg.sender == owner
    /// @custom:strata ensures owner == address(0)
    /// @custom:strata modifies owner
    function renounceOwnership() external {
        require(msg.sender == owner, "not owner");
        owner = address(0);
    }
}
