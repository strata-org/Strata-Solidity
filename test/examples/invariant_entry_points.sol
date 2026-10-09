// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Contract invariants hold between transactions: external entry points
// assume them on entry and re-establish them on exit, view functions may
// rely on them, and internal helpers (which run in the middle of an entry
// point) neither assume nor re-establish them.
contract InvariantEntryPoints {
    /// @custom:strata invariant a == b
    uint256 public a;
    uint256 public b;

    /// @custom:strata ensures a == old(a) + v
    function bumpBoth(uint256 v) public {
        a += v;
        b += v;
    }

    // Leaves `a == b` broken; only an entry point must restore it.
    function _setA(uint256 v) internal {
        a = v;
    }

    /// @custom:strata ensures r == 0
    function diff() public view returns (uint256 r) {
        r = a - b;
    }
}

// A view function assumes the invariant, which here sums a mapping that no
// mutating function touches: sum() is still declared.
/// @custom:strata invariant total == sum(balances)
contract ViewOnlySum {
    mapping(address => uint256) public balances;
    uint256 public total;

    /// @custom:strata ensures r == sum(balances)
    function totalSupply() external view returns (uint256 r) {
        r = total;
    }
}
