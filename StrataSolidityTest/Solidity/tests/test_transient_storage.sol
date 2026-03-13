// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// NOTE: Requires solc 0.8.28+. May fail to parse on older versions — that's expected.

contract TransientGuard {
    uint256 transient lockFlag;

    modifier nonReentrant() {
        require(lockFlag == 0, "reentrant");
        lockFlag = 1;
        _;
        lockFlag = 0;
    }

    /// @custom:strata ensures lockFlag == 0
    function guarded() external nonReentrant {
        // body
    }
}
