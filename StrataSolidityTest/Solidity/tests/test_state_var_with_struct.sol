// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: Contract with struct type and state variables of various types,
/// including a user-defined struct type.
contract ContractWithFields {
    struct Info {
        uint256 value;
        bool flag;
    }

    uint256 public count;
    bool public paused;
    Info public data;

    function checkPure(uint256 a, uint256 b) public pure returns (uint256) {
        require(a <= 1000);
        require(b <= 1000);
        uint256 sum = a + b;
        assert(sum >= a);
        return sum;
    }
}
