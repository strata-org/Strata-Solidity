// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A base in another file contributes no members here: its state,
// constructor, functions and invariant are not part of what is verified,
// for the contract that names it and for every contract inheriting it
// through another one. Both are reported.

import "./lib/Ownable.sol";

contract Borrowed is Ownable {
    uint256 public own;

    // Passes.
    /// @custom:strata ensures own == v
    function setOwn(uint256 v) external {
        own = v;
    }
}

contract Lent is Borrowed {
    // Refuted: `own` is `v`.
    /// @custom:strata ensures own == v + 1
    function setOwnWrong(uint256 v) external {
        own = v;
    }
}
