// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Annotations the translator cannot use must be reported, never dropped
// silently. Every `@custom:strata` line below except the `ensures` on
// `increment` and on `sum` produces a warning (test/expected/
// ignored_annotations.warnings); `--strict` turns them into a failing exit.
// Mentioning @custom:strata in prose, as here, is not an annotation.

/// @custom:strata ensures count >= 0
contract IgnoredAnnotations {
    uint256 public count;

    /// @custom:strata invariant count >= 0

    /// @custom:strata ensure count == old(count) + 1
    /// @custom:strata ensures count == old(count) + 1
    function increment() external {
        count += 1;
        emit Counted("verified with @custom:strata annotations");
    }

    // @custom:strata ensures count == 0
    function reset() external {
        count = 0;
    }

    /// @custom:strata loop-invariant i <= n
    /// @custom:strata loop-invariant s == i
    /// @custom:strata ensures s == n
    function sum(uint256 n) external pure returns (uint256 s) {
        s = 0;
        /// @custom:strata loop-invariant s <= n
        for (uint256 i = 0; i < n; i++) {
            s += 1;
        }
    }

    /// @custom:strata loop-invariant count == 7
    function noLoop() external {
        count = count;
    }

    /// @custom:strata modifies count
    constructor() {
        count = 0;
    }

    /// @custom:strata ensures count == 12345
    modifier onlyOnce() {
        _;
    }

    /// @custom:strata invariant count == 7
    event Counted(string note);

    /// @custom:strata
    ///   ensures count == 1
    function bareTag() external {
        count = 1;
    }

    /// @custom:strata invariant count < 2
}

// How a comment is written does not affect which annotations are found:
// a trailing NatSpec comment is read (solc attaches it to the next
// declaration), a tag in the middle of a NatSpec line is not, and a
// trailing comment after the last member is attached to nothing.
contract CommentPlacement {
    struct Position { uint256 amount; }
    mapping(address => Position) public balance;
    uint256 public x; /// @custom:strata ensures x == v
    function setX(uint256 v) external { x = v; }

    /// Sets x. @custom:strata ensures x == 99
    function midLine() external { x = 1; }

    // A string that reads like the struct-valued mapping is not a use of it.
    /// @custom:strata ensures x == old(x) + 1
    function bump() external { x += 1; require(x > 0, "balance"); }

    /// @custom:strata modifies x, balance[who +]
    function frame(address who) external { x = 2; }

    function setY(uint256 v) external { x = v; } /// @custom:strata invariant x == 7
}
