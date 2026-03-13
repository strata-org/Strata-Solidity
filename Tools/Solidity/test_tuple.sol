// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TupleTest {
    function getTwo() internal pure returns (uint256, uint256) {
        return (1, 2);
    }

    function testTupleDestructure() public pure {
        (uint256 a, uint256 b) = getTwo();
        require(a + b > 0);
    }

    function testLowLevelCall(address target) public {
        (bool success, ) = target.call("");
        require(success);
    }
}
