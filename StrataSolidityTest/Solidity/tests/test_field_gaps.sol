// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }
}

abstract contract Base {
    uint256 public immutable deployTime;
    uint256 public constant MAX_SUPPLY = 1000000;

    constructor() {
        deployTime = block.timestamp;
    }

    function name() external virtual pure returns (string memory);
}

contract Derived is Base {
    using SafeMath for uint256;

    uint256 private _supply;

    function name() external pure override returns (string memory) {
        return "Derived";
    }

    function mint(uint256 amount) external {
        _supply = _supply.add(amount);
    }
}
