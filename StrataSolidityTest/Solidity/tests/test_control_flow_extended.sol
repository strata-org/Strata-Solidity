// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExternal {
    function riskyCall() external returns (uint256);
}

contract ControlFlowExtended {
    uint256 public counter;
    uint256 public lastResult;
    bool public callFailed;

    /// @custom:strata ensures counter >= 1
    function doWhileLoop() external {
        uint256 i = 0;
        do {
            i += 1;
        } while (i < 5);
        counter = i;
    }

    function loopWithBreak(uint256[] calldata data) external pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < data.length; i++) {
            if (data[i] == 0) {
                break;
            }
            sum += data[i];
        }
        return sum;
    }

    function loopWithContinue(uint256[] calldata data) external pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < data.length; i++) {
            if (data[i] > 1000) {
                continue;
            }
            sum += data[i];
        }
        return sum;
    }

    function tryCatchExternal(address target) external {
        try IExternal(target).riskyCall() returns (uint256 val) {
            lastResult = val;
            callFailed = false;
        } catch Error(string memory) {
            callFailed = true;
        } catch {
            callFailed = true;
        }
    }
}
