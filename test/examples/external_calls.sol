// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Calls that run code outside the contract. A mutating one may call back
// into the contract (re-enter it) and change its state through its
// external functions: the state is unknown after the call, except for the
// contract invariants, which are checked before the call and assumed after.
// View calls, `staticcall`, `send` and `transfer` change nothing;
// `delegatecall` may change anything.

interface IToken {
    function balanceOf(address who) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract Child {}

/// @custom:strata invariant fee <= 100
contract Bank {
    IToken public immutable token;
    uint256 public fee;

    // A constructor's calls cannot be re-entered: the contract has no code yet.
    /// @custom:strata ensures fee == 1
    constructor(IToken t) {
        token = t;
        fee = 1;
        t.transfer(msg.sender, 0);
    }

    function setFee(uint256 f) external {
        require(f <= 100);
        fee = f;
    }

    // A view call changes nothing; its result is a uint256.
    /// @custom:strata ensures fee == old(fee)
    /// @custom:strata ensures b >= 0
    /// @custom:strata ensures address(this) != address(0)
    function held() external returns (uint256 b) {
        b = token.balanceOf(address(this));
    }

    // A re-entrant call may have called setFee: fee is unknown afterwards
    // (the first ensures fails), but the invariant still holds, and an
    // immutable keeps its value.
    /// @custom:strata ensures fee == old(fee)
    /// @custom:strata ensures fee <= 100
    /// @custom:strata ensures token == old(token)
    function pay(address to, uint256 amount) external {
        require(token.transfer(to, amount));
    }

    // The invariant must hold when the contract is re-entered: it does not
    // hold before this call.
    function unsafePay(address to) external {
        fee = 200;
        require(token.transfer(to, 1));
        fee = 50;
    }

    // `this.f()` is an external call too.
    /// @custom:strata ensures fee <= 100
    function viaThis() external {
        this.setFee(5);
    }

    /// @custom:strata ensures fee == old(fee)
    function lowLevelStatic(address a, bytes calldata d) external {
        (bool ok, ) = a.staticcall(d);
        require(ok);
    }

    /// @custom:strata ensures fee <= 100
    function lowLevelCall(address payable a) external {
        (bool ok, ) = a.call{value: 1}("");
        require(ok);
    }

    // `delegatecall` runs other code on this contract's storage: even the
    // invariant is unknown afterwards (this ensures and the invariant fail).
    /// @custom:strata ensures fee <= 100
    function delegated(address a, bytes calldata d) external {
        (bool ok, ) = a.delegatecall(d);
        require(ok);
    }

    // The callee of `send` and `transfer` gets too little gas to change state.
    /// @custom:strata ensures fee == old(fee)
    function sendEther(address payable a) external {
        a.transfer(1);
        require(a.send(1));
    }

    // A call that reverts undoes what it did: in the catch clause, the
    // state is the one before the call.
    function tryPay(address to) external {
        uint256 before = fee;
        try token.transfer(to, 1) returns (bool) {
        } catch {
            assert(fee == before);
        }
    }

    // The new contract's constructor may call back into this one.
    /// @custom:strata ensures fee == old(fee)
    function create() external returns (address c) {
        c = address(new Child());
    }
}
