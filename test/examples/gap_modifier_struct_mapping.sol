// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: a modifier that uses a struct-valued mapping stops the
// translation of the whole file. (A function that uses one directly is not
// verified, and is reported: gap `struct-mapping`.) Gap
// `modifier-struct-mapping` in docs/capabilities.toml.
contract GapModifierStructMapping {
    struct User { bool banned; }
    mapping(address => User) public users;
    uint256 public x;

    modifier notBanned() {
        require(!users[msg.sender].banned);
        _;
    }

    /// @custom:strata ensures x == 1
    function act() external notBanned {
        x = 1;
    }
}
