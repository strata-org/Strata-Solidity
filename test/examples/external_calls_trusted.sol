// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Run with `--assume-no-reentrancy` (see external_calls_trusted.flags):
// external calls are trusted not to call back into the contract, so they
// leave its state unchanged, and the invariants need not hold at a call.
// `delegatecall` still runs other code on the contract's storage.

interface IToken {
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @custom:strata invariant fee <= 100
contract TrustedBank {
    IToken public token;
    uint256 public fee;

    function setFee(uint256 f) external {
        require(f <= 100);
        fee = f;
    }

    /// @custom:strata ensures fee == old(fee)
    function pay(address to, uint256 amount) external {
        require(token.transfer(to, amount));
    }

    // The invariant is broken during the call, which is trusted not to
    // re-enter.
    function midway(address to) external {
        fee = 200;
        require(token.transfer(to, 1));
        fee = 50;
    }

    // Refuted, as without the flag.
    /// @custom:strata ensures fee == old(fee)
    function delegated(address a, bytes calldata d) external {
        (bool ok, ) = a.delegatecall(d);
        require(ok);
    }
}
