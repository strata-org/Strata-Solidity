// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: an `if`/`else` (or `try`/`catch`) whose branches end with
// assignments of different types stops the translation of the whole file
// ("'if' branches have incompatible types"). Gap `branch-types` in
// docs/capabilities.toml.
contract GapBranchTypes {
    uint256 public count;
    bool public stopped;

    /// @custom:strata ensures !stop ==> count == old(count) + 1
    function step(bool stop) external {
        if (!stop) {
            count += 1;
        } else {
            stopped = true;
        }
    }
}
