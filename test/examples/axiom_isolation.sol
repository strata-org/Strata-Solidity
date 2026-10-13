// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// The constructor zero-initializes a mapping, which brings Core's
// quantified `mapConst` axiom into its verification conditions. Each
// function (each overload too) is verified separately, so that axiom does
// not reach `addWrong`, whose false postcondition must be refuted (not
// `unknown`). The checks that a function's `requires` and `ensures` are
// well defined (no division by zero) are verified with it.
contract AxiomIsolation {
    mapping(address => uint256) public balances;
    uint256 public total;

    /// @custom:strata ensures balances[msg.sender] == 0
    /// @custom:strata ensures total == 0
    constructor() {
        total = 0;
    }

    /// @custom:strata ensures r == a + b + 1
    function addWrong(uint256 a, uint256 b) public pure returns (uint256 r) {
        r = a + b;
    }

    function touch(address to) public {
        balances[to] = 1;
    }

    // An overload of `touch`.
    function touch(address to, uint256 v) public {
        balances[to] = v;
    }

    // Refuted: `a / b` in the `ensures` divides by zero when b == 0.
    /// @custom:strata ensures r == a / b
    function ratio(uint256 a, uint256 b) public pure returns (uint256 r) {
        r = b == 0 ? 0 : a / b;
    }
}
