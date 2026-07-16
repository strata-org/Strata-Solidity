// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Regression guard for named-constant folding in SPEC expressions and in
// key-scoped modifies clauses. Constants are removed from the contract's
// fields (they are compile-time values), so without folding they reached
// Laurel->Core as unresolved identifiers (ReentrancyGuard / AccessControl
// blocker).
contract SpecConstants {
    uint256 public constant NOT_ENTERED = 1;
    uint256 public constant ENTERED = 2;
    bytes32 public constant DEFAULT_ROLE = 0x00;

    uint256 public status;
    mapping(bytes32 => bool) public flags;

    /// @custom:strata requires status == NOT_ENTERED
    /// @custom:strata modifies status
    /// @custom:strata ensures status == ENTERED
    function enter() external {
        require(status == NOT_ENTERED, "reentrant");
        status = ENTERED;
    }

    /// @custom:strata requires flags[DEFAULT_ROLE] == false
    /// @custom:strata modifies flags[DEFAULT_ROLE]
    /// @custom:strata ensures flags[DEFAULT_ROLE] == true
    function setDefault() external {
        require(!flags[DEFAULT_ROLE], "set");
        flags[DEFAULT_ROLE] = true;
    }
}
