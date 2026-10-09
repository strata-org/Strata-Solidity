// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// `lib/Math.sol` sorts before this file. solc reports every source unit;
// the verified one must be this file, not the first in the list.
import "./lib/Math.sol";

contract ImportOrder {
    uint256 public total;

    /// @custom:strata ensures total == old(total) + amount
    function add(uint256 amount) external {
        total += amount;
    }

    // Refuted: proves that this file, not the import, was verified.
    /// @custom:strata ensures total == old(total)
    function bump() external {
        total += 1;
    }
}
