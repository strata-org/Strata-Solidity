// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ExpressionExtras {
    uint256 public constant ONE_ETHER = 1 ether;
    uint256 public constant ONE_DAY = 1 days;
    uint256 public constant TWO_WEEKS = 2 weeks;

    /// @custom:strata ensures ONE_ETHER == 1000000000000000000
    function checkEtherUnit() external pure returns (uint256) {
        return 1 ether;
    }

    function checkTimeUnits() external pure returns (uint256) {
        return 1 hours + 30 minutes;
    }

    function inlineArrayExample() external pure returns (uint256) {
        uint256[3] memory arr = [uint256(10), 20, 30];
        return arr[0] + arr[1] + arr[2];
    }

    function sliceExample(bytes calldata data) external pure returns (bytes memory) {
        return data[1:5];
    }
}
