// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Enum support — enums modeled as constrained integers.
contract EnumTest {
    enum Status { Active, Inactive, Paused }

    Status public currentStatus;

    function setStatus(Status s) public {
        currentStatus = s;
    }

    function isActive() public view returns (bool) {
        return currentStatus == Status.Active;
    }

    function getInactive() public pure returns (Status) {
        return Status.Inactive;
    }
}
