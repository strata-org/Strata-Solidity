// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A function without a body here (virtual, implemented by a derived
// contract) may do anything a function of its kind may: a mutating one may
// change the contract's state, so what the caller wrote before calling it
// is not known afterwards.
abstract contract VirtualFunctions {
    uint256 public x;
    mapping(address => uint256) public balances;

    function _hook(address who) internal virtual;
    function _peek() internal view virtual returns (uint256);

    // Not proven: `_hook` may change `x`.
    /// @custom:strata ensures x == 5
    function setThenHook(address who) external {
        x = 5;
        _hook(who);
    }

    // Not proven: `_hook` may change `balances`.
    /// @custom:strata ensures balances[who] == old(balances[who])
    function balanceAfterHook(address who) external {
        _hook(who);
    }

    // Passes: a view function changes nothing.
    /// @custom:strata ensures x == 5
    function setThenPeek() external returns (uint256 r) {
        x = 5;
        r = _peek();
    }
}
