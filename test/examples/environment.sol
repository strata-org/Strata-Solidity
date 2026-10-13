// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Transaction values (`block.*`, `tx.*`) are fixed for the whole
// transaction; `gasleft()`, balances and the outcome of `send` may differ
// at every read. All of them hold values of their Solidity type.
contract Environment {
    uint256 public deadline;

    // Passes: both reads see the same timestamp.
    /// @custom:strata ensures r == 0
    function sameTimestamp() external view returns (uint256 r) {
        uint256 a = block.timestamp;
        uint256 b = block.timestamp;
        r = a - b;
    }

    // Passes: specs can read them too.
    /// @custom:strata requires block.timestamp < deadline
    /// @custom:strata ensures r
    function isOpen() external view returns (bool r) {
        r = block.timestamp < deadline;
    }

    // Passes: tx.origin is an address.
    /// @custom:strata ensures r <= type(uint160).max
    function origin() external view returns (address r) {
        r = tx.origin;
    }

    // Fails: the gas left differs between the two calls.
    /// @custom:strata ensures r
    function sameGas() external view returns (bool r) {
        uint256 a = gasleft();
        uint256 b = gasleft();
        r = a == b;
    }

    // Passes: a balance is a uint256.
    /// @custom:strata ensures r <= type(uint256).max
    function balance() external view returns (uint256 r) {
        r = address(this).balance;
    }

    // Passes: `this` is the contract's address, a nonzero constant of the
    // transaction, and a value of a contract type is an address.
    /// @custom:strata ensures r == (address(e) == address(this))
    /// @custom:strata ensures address(this) != address(0)
    function isSelf(Environment e) external view returns (bool r) {
        r = e == this;
    }

    // Fails: a send may fail.
    /// @custom:strata ensures ok
    function pay(address payable to) external returns (bool ok) {
        ok = to.send(1);
    }
}
