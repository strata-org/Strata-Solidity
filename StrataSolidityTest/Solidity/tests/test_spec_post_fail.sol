// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Postcondition failure test.
/// The postcondition claims result == a + b + 1, but body returns a + b.
contract SpecPostFail {

    // Strata specification stubs
    function _strata_post(bool) internal pure {}

    function wrongPost(uint256 a, uint256 b) public pure returns (uint256 result) {
        _strata_post(result == a + b + 1);

        require(a <= 10000, "a too large");
        require(b <= 10000, "b too large");
        result = a + b;
    }
}
