// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A tuple declaration `(T a, T b) = init;` declares its variables for the
// rest of the block. An internal call binds its return values to them (and
// still runs, with its effects on state); a tuple initializes each variable
// with its component.
contract TupleDeclarations {
    mapping(address => uint256) public balances;

    /// @custom:strata ensures a == x && b == y
    function _pair(uint256 x, uint256 y) internal pure returns (uint256 a, uint256 b) {
        a = x;
        b = y;
    }

    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    /// @custom:strata ensures ok
    function _credit(address to, uint256 amount) internal returns (bool ok, uint256 total) {
        balances[to] += amount;
        ok = true;
        total = balances[to];
    }

    /// @custom:strata ensures r == 3
    function fromCall() external pure returns (uint256 r) {
        (uint256 p, uint256 q) = _pair(1, 2);
        r = p + q;
    }

    /// @custom:strata ensures r == 3
    function fromTuple() external pure returns (uint256 r) {
        (uint256 p, uint256 q) = (1, 2);
        r = p + q;
    }

    // Refuted: the call runs, even with a skipped slot.
    /// @custom:strata requires amount > 0
    /// @custom:strata ensures balances[to] == old(balances[to])
    function skipped(address to, uint256 amount) external {
        (bool ok, ) = _credit(to, amount);
    }
}
