// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LoopOld {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    /// @custom:strata modifies totalSupply
    /// @custom:strata ensures totalSupply == old(totalSupply) + n
    /// @custom:strata loop-invariant totalSupply == old(totalSupply) + i
    function addN(uint256 n) external {
        for (uint256 i = 0; i < n; i++) {
            totalSupply += 1;
        }
    }
}
