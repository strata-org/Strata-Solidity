// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Exercises FunctionCallOptions ({value, gas}) and dynamic-array
// NewExpression (`new uint[](n)`) through the real verification harness.
// Contract-creation NewExpression returning a typed reference needs deeper
// type modeling (issue #14 treats it as opaque) and is covered only at the
// sol_to_strata level in StrataSolidityTest/.../test_calls_creation.sol.
contract CallsCreation {
    uint256 public lastSent;

    /// @custom:strata ensures lastSent == amount
    function sendEther(address payable target, uint256 amount) external {
        target.call{value: amount, gas: 50000}("");
        lastSent = amount;
    }

    /// @custom:strata ensures len == n
    function allocate(uint256 n) external pure returns (uint256 len) {
        uint256[] memory arr = new uint256[](n);
        len = n;
    }
}
