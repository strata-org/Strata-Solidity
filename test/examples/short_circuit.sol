// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// `&&` and `||` evaluate their right operand only when needed: its calls
// and checks happen only on those paths, in code and in specs.
contract ShortCircuit {
    mapping(address => uint256) public counts;

    /// @custom:strata ensures counts[who] == old(counts[who]) + 1
    /// @custom:strata ensures ok
    function _bump(address who) internal returns (bool ok) {
        counts[who] += 1;
        return true;
    }

    /// @custom:strata requires x > 0
    /// @custom:strata ensures ok
    function _positive(uint256 x) internal pure returns (bool ok) {
        return true;
    }

    // Fails: with x == 0, `_bump` is not called.
    /// @custom:strata ensures counts[who] == old(counts[who]) + 1
    function bumpIfPositive(address who, uint256 x) external {
        if (x > 0 && _bump(who)) {}
    }

    // Passes: with x != 0, `_bump` is not called.
    /// @custom:strata ensures x != 0 ==> counts[who] == old(counts[who])
    function bumpIfZero(address who, uint256 x) external {
        if (x != 0 || _bump(who)) {}
    }

    // Passes: the division and the call's precondition are guarded.
    /// @custom:strata ensures r == (b != 0 && a / b > 1)
    function guarded(uint256 a, uint256 b) external pure returns (bool r) {
        r = b != 0 && a / b > 1 && _positive(b);
    }
}
