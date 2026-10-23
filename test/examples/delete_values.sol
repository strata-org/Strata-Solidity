// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// `delete` sets an integer, an address or a mapping entry to zero. (Of a
// `bool`, an array or a struct, it is not supported: see
// gap_delete_non_integer.sol.)
contract DeleteValues {
    uint256 public count;
    address public owner;
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowance;

    // Passes: each deleted value is zero.
    /// @custom:strata ensures count == 0 && owner == address(0)
    /// @custom:strata ensures balances[a] == 0 && allowance[a][b] == 0
    function reset(address a, address b) external {
        delete count;
        delete owner;
        delete balances[a];
        delete allowance[a][b];
    }

    // Passes: only the deleted entry changes.
    /// @custom:strata requires c != a
    /// @custom:strata ensures balances[c] == old(balances[c])
    function resetOne(address a, address c) external {
        delete balances[a];
    }

    // Refuted: the entry is zero after `delete`.
    /// @custom:strata ensures balances[a] == old(balances[a])
    function resetWrong(address a) external {
        delete balances[a];
    }
}
