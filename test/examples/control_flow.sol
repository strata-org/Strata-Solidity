// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Exercises do-while, break, and continue through the real verification
// harness. Specs are chosen to be provable under the loop translation.
contract ControlFlow {
    /// @custom:strata ensures result >= 1
    function doWhileCount() external pure returns (uint256 result) {
        result = 0;
        do {
            result = result + 1;
        } while (result < 5);
    }

    /// @custom:strata requires n >= 0
    /// @custom:strata ensures found == true || found == false
    function scanWithBreak(uint256 n) external pure returns (bool found) {
        found = false;
        for (uint256 i = 0; i < n; i++) {
            if (i == 3) {
                found = true;
                break;
            }
        }
    }

    /// @custom:strata requires n >= 0
    function sumSkippingWithContinue(uint256 n) external pure returns (uint256 total) {
        total = 0;
        for (uint256 i = 0; i < n; i++) {
            if (i == 0) {
                continue;
            }
            total = total + 1;
        }
    }
}
