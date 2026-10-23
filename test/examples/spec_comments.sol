// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A `//` after an annotation's expression starts a comment, as in the
// guide's examples (`ensures … // ✅ SUPPORTED`). Such a comment used to
// abort the translation of the whole file ("Unexpected tokens after spec
// expression"), and non-ASCII text in it came out garbled (`✅AA`), because
// the spec tokenizer mixed byte and character positions.
contract SpecComments {
    uint256 public x;
    mapping(address => uint256) public balances;

    // Passes: the comment is not part of the postcondition.
    /// @custom:strata ensures x == v  // ✅ the stored value
    function set(uint256 v) external {
        x = v;
    }

    // Refuted: the same form, on a false postcondition.
    /// @custom:strata ensures x == v + 1  // ❌ off by one
    function setWrong(uint256 v) external {
        x = v;
    }

    // Passes: comments after `requires` and `modifies` (non-ASCII text, a
    // `/` and a mapping in the comment are not read either).
    /// @custom:strata requires v < 10  // café: v ≤ 9, x / 2 < balances[a]
    /// @custom:strata modifies x  // nothing else changes
    /// @custom:strata ensures x < 10
    function setSmall(uint256 v) external {
        x = v;
    }

    // Refuted: the comment after `modifies` does not widen the frame, so
    // writing `balances` breaks it.
    /// @custom:strata modifies x  // and balances[msg.sender]
    function setBoth(uint256 v) external {
        x = v;
        balances[msg.sender] = v;
    }
}
