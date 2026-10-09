// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A modifier is inlined into each function using it, the first one
// outermost: its body runs with `_` standing for the rest, its parameters
// bound to the arguments of the use, its `require`s (like the function's
// own) pruning the paths where they fail. A `return` in the function body
// ends the body only: the code after `_` still runs.
contract Modifiers {
    bool private locked;
    uint256 public count;
    uint256 public limit = 100;
    address public owner;
    mapping(address => bool) public admins;

    modifier nonReentrant() {
        require(!locked);
        locked = true;
        _;
        locked = false;
    }

    modifier atMost(uint256 limit) {
        require(count + 1 <= limit);
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender]);
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier thenAddTen() {
        _;
        count = count + 10;
    }

    /// @custom:strata ensures count == old(count) + 1
    /// @custom:strata ensures !locked
    function bump() external nonReentrant {
        count += 1;
    }

    // Refuted: this `limit` is the argument 1000, not the state variable.
    /// @custom:strata ensures count <= 100
    function bumpBounded() external atMost(1000) {
        count += 1;
    }

    /// @custom:strata ensures admins[msg.sender]
    function adminOnly() external onlyAdmin {
    }

    /// @custom:strata ensures r == 5 && count == old(count) + 10
    function returnsEarly() external thenAddTen returns (uint256 r) {
        return 5;
    }

    /// @custom:strata ensures count == 1
    function grant() public onlyOwner {
        count = 1;
    }

    // The callee's modifiers are part of the callee: its `require` is not
    // the caller's to establish.
    /// @custom:strata ensures count == 1
    function grantFromHere() external {
        grant();
    }
}
