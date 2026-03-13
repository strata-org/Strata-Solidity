// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Tests interface declarations, abstract contracts, external calls, and new-expression.

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

abstract contract Base {
    uint256 public value;
    function foo() public virtual returns (uint256);
}

contract Child is Base {
    function foo() public override returns (uint256) {
        return value + 1;
    }

    /// @custom:strata requires amount > 0
    function doTransfer(address token, address to, uint256 amount) external returns (bool) {
        return IERC20(token).transfer(to, amount);
    }

    function lowLevelCalls(address target) external returns (bool) {
        (bool s1,) = target.call("");
        (bool s2,) = target.delegatecall("");
        (bool s3,) = target.staticcall("");
        return s1 && s2 && s3;
    }
}
