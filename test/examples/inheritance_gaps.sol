// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// What inheritance does not cover is reported, not assumed away.

import "./lib/Ownable.sol";

// A base in another file contributes no members here: `Ownable`'s state,
// constructor and invariant are not part of what is verified for this
// contract.
contract Borrowed is Ownable {
    uint256 public own;

    /// @custom:strata ensures own == v
    function setOwn(uint256 v) external {
        own = v;
    }
}

// A base constructor that takes arguments is bound by the derived
// contract's `Priced(...)` clause, which is not modelled: it does not run,
// so the invariant it would establish is not proven.
/// @custom:strata invariant price == 7
contract Priced {
    uint256 public price;

    constructor(uint256 p) {
        price = p;
    }
}

contract Item is Priced {
    constructor() Priced(7) {}

    /// @custom:strata ensures r == price
    function priceOf() external view returns (uint256 r) {
        r = price;
    }
}
