// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Only the `require`s before `_;` of a modifier are modelled (as
// preconditions, with the modifier's parameters bound to the arguments of
// each use). The lock write and its release are not, which is reported at
// each use (test/expected/unmodelled_modifier.warnings) so that --strict
// fails rather than trusting `ensures` that ignore the modifier.
contract UnmodelledModifier {
    bool private locked;
    uint256 public count;
    uint256 public limit = 100;
    mapping(address => bool) public admins;

    modifier nonReentrant() {
        require(!locked);
        locked = true;
        _;
        locked = false;
    }

    // Partly modelled but never used: nothing to report.
    modifier counted() {
        count += 1;
        _;
    }

    modifier atMost(uint256 limit) {
        require(count + 1 <= limit);
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender]);
        _;
    }

    /// @custom:strata ensures count == old(count) + 1
    function bump() external nonReentrant {
        count += 1;
    }

    // Refuted: this `limit` is the argument 1000, not the state variable.
    /// @custom:strata ensures count <= 100
    function bumpBounded() external atMost(1000) {
        count += 1;
    }

    /// @custom:strata ensures count == old(count) + 1
    function adminBump() external onlyAdmin {
        count += 1;
    }
}
