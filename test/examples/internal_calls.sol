// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Internal calls pass the callee's implicit inputs in its declared order,
// bind named arguments by name, and bind a mutating callee's mapping
// outputs back to the caller. A write whose right-hand side calls such a
// callee happens after the call. Calls are modular: the caller knows what
// the callee's `ensures` say.
contract InternalCalls {
    mapping(address => uint256) public balances;
    uint256 public total;

    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    /// @custom:strata ensures total == old(total) + amount
    function _credit(address to, uint256 amount) internal {
        balances[to] += amount;
        total += amount;
    }

    /// @custom:strata ensures r == 2 * x
    function _twice(uint256 x) internal pure returns (uint256 r) {
        r = 2 * x;
    }

    /// @custom:strata ensures s == msg.sender
    function _sender() internal view returns (address s) {
        s = msg.sender;
    }

    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    function deposit(address to, uint256 amount) external {
        _credit(to, amount);
    }

    // Refuted: the helper's mapping write is visible to the caller.
    /// @custom:strata ensures balances[to] == old(balances[to])
    function depositWrong(address to, uint256 amount) external {
        require(amount > 0);
        _credit(to, amount);
    }

    /// @custom:strata ensures r == 2 * x
    function twice(uint256 x) external pure returns (uint256 r) {
        r = _twice(x);
    }

    /// @custom:strata ensures who == msg.sender
    function whoAmI() external view returns (address who) {
        who = _sender();
    }

    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    function depositByName(address to, uint256 amount) external {
        _credit({amount: amount, to: to});
    }

    /// @custom:strata ensures balances[who] == 9
    /// @custom:strata ensures r == 6
    function _set(address who) internal returns (uint256 r) {
        balances[who] = 9;
        r = 6;
    }

    // The callee's write to balances[b] is kept: the caller's write to
    // balances[a] happens after the call.
    /// @custom:strata requires a != b
    /// @custom:strata ensures balances[a] == 6 && balances[b] == 9
    function writeAfterCall(address a, address b) external {
        balances[a] = _set(b);
    }
}
