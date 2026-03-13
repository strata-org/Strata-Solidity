// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// NOTE: try/catch may produce AST nodes the translator skips gracefully.

interface IExternal {
    function riskyCall() external returns (uint256);
}

contract TryCatch {
    uint256 public lastResult;
    bool public callFailed;

    /// @custom:strata ensures callFailed == true || lastResult > 0
    function attempt(address target) external {
        try IExternal(target).riskyCall() returns (uint256 val) {
            lastResult = val;
            callFailed = false;
        } catch {
            callFailed = true;
        }
    }
}
