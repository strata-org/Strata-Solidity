// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// What the translator does not model is unknown, and unknown afresh at
// every evaluation (a value computed in a loop may differ between
// iterations): a new contract or array, a low-level call's result, a
// try/catch outcome, a slice. `selfdestruct` ends the function.
contract UnknownValues {
    uint256 public x;

    // Refuted: `selfdestruct` ends the function before the write.
    /// @custom:strata ensures x == 1
    function destroy(address payable to) external {
        selfdestruct(to);
        x = 1;
    }

    // Refuted: the call may fail.
    /// @custom:strata ensures ok
    function callResult(address to) external returns (bool ok) {
        (ok, ) = to.call("");
    }
}
