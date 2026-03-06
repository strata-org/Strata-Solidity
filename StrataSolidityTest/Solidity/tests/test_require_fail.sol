// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract RequireFail {
    function must_be_positive(uint256 x) public pure returns (uint256) {
        require(x > 0, "must be positive");
        // This assertion should fail: x > 0 does not imply x > 100
        assert(x > 100);
        return x;
    }
}
