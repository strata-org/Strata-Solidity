// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Tests external call handling via interface.

interface IToken {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract CrossCaller {
    /// @custom:strata requires amount > 0
    function doTransfer(address token, address to, uint256 amount) external returns (bool) {
        return IToken(token).transfer(to, amount);
    }
}
