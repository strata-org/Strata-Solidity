// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Rejected: a constructor that calls an internal function reading or
// writing state (the ERC-20 `_mint` pattern) stops the translation of the
// whole file. Gap `constructor-internal-call` in docs/capabilities.toml.
contract GapConstructorCall {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    constructor(uint256 initial) {
        _mint(msg.sender, initial);
    }

    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balances[to] += amount;
    }
}
