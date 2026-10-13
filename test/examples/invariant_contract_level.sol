// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Contract invariants may be written in the NatSpec above `contract`.
// solc attaches each NatSpec block to exactly one declaration, so each
// contract in a file gets its own invariants. Interfaces and libraries
// have no state: an invariant there is reported, not assumed.

/// @custom:strata invariant reserve >= minReserve
contract Pool {
    uint256 public reserve;
    uint256 public minReserve;

    function deposit(uint256 amount) external {
        reserve += amount;
    }

    /// @custom:strata requires amount <= reserve - minReserve
    function withdraw(uint256 amount) external {
        reserve -= amount;
    }
}

/// @custom:strata invariant count <= limit
contract Counter {
    uint256 public count;
    uint256 public limit = 10;

    function increment() external {
        require(count < limit);
        count += 1;
    }
}

/// @custom:strata invariant 1 == 2
interface IPool {
    function deposit(uint256 amount) external;
}

/// @custom:strata invariant 1 == 2
library Math {
    // Also not assumed when attached to a library constant: the false
    // ensures below is refuted.
    /// @custom:strata invariant LIMIT == 7
    uint256 constant LIMIT = 5;

    /// @custom:strata ensures r == a
    function id(uint256 a) internal pure returns (uint256 r) {
        r = a;
    }

    /// @custom:strata ensures r == 12345
    function wrong(uint256 a) external pure returns (uint256 r) {
        r = a;
    }
}
