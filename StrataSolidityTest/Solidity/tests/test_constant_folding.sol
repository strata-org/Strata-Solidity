// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Constant state variables are folded to their values.
/// Also tests type(uint256).max as a constant initializer.
contract ConstantFolding {
    uint256 public constant MAX_SUPPLY = 1000000;
    uint256 public constant UINT_MAX = type(uint256).max;
    uint256 public totalSupply;

    function mint(uint256 amount) public {
        require(totalSupply + amount <= MAX_SUPPLY);
        totalSupply = totalSupply + amount;
        assert(totalSupply <= 1000000);
    }

    function checkUintMax() public pure returns (uint256) {
        uint256 x = UINT_MAX;
        assert(x > 0);
        return x;
    }
}
