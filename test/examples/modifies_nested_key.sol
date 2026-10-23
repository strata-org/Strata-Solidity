// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A key-scoped `modifies` names one key of a mapping: `modifies m[k]`
// allows `m[k]` to change, and with a nested mapping, every `m[k][…]`.
// A key with two indexes (`m[a][b]`) cannot be read, so the frame of that
// mapping is not checked at all, which is reported.
contract ModifiesNestedKey {
    mapping(address => mapping(address => uint256)) public allowance;

    // Passes: the write is in the row of `owner`.
    /// @custom:strata modifies allowance[owner]
    function approve(address owner, address spender, uint256 v) external {
        allowance[owner][spender] = v;
    }

    // Refuted: the write is in another owner's row.
    /// @custom:strata requires other != owner
    /// @custom:strata modifies allowance[owner]
    function approveOther(address owner, address other, address spender, uint256 v) external {
        allowance[other][spender] = v;
    }

    // The frame `allowance[owner][spender]` is not checked (warning), so
    // this write to another row is not reported.
    /// @custom:strata requires other != owner
    /// @custom:strata modifies allowance[owner][spender]
    function approveTwoKeys(address owner, address other, address spender, uint256 v) external {
        allowance[other][spender] = v;
    }
}
