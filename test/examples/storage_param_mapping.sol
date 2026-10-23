// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A mapping `storage` parameter refers to the caller's storage:
// `_credit(balances, k)` writes `balances[k]`. It was modelled as a local
// copy, so the write was lost: `bump`'s wrong postcondition was proven and
// `bumpTrue`'s correct one was not. The file is now rejected.
contract StorageParamMapping {
    mapping(address => uint256) public balances;
    uint256 public total;

    /// @custom:strata modifies total
    function _credit(mapping(address => uint256) storage m, address k) internal {
        m[k] += 1;
        total += 1;
    }

    // Wrong: balances[k] grows by one.
    /// @custom:strata ensures balances[k] == old(balances[k])
    function bump(address k) external {
        _credit(balances, k);
    }

    // Holds.
    /// @custom:strata ensures balances[k] == old(balances[k]) + 1
    function bumpTrue(address k) external {
        _credit(balances, k);
    }
}
