// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title AccessControl
/// @notice Ownable with transferOwnership — should PASS verification.
contract AccessControl {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    /// @custom:strata requires msg.sender == owner
    /// @custom:strata requires newOwner != address(0)
    /// @custom:strata ensures owner == newOwner
    /// @custom:strata modifies owner
    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "Not owner");
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }
}
