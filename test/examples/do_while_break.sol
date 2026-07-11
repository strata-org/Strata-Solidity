// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Regression guard for do-while + break label placement.
// A break in the FIRST iteration must exit the whole loop. Previously the
// first iteration sat OUTSIDE the break/continue-labelled blocks, so its
// Exit was uncaught, fell through into the while replay, and re-ran the
// body — yielding count == 2 here (and non-termination reasoning on
// `while (true)`). `ensures result == 1` is provable only with correct
// break semantics.
contract DoWhileBreak {
    /// @custom:strata ensures result == 1
    function firstIterBreak() public pure returns (uint256 result) {
        uint256 count = 0;
        do {
            count += 1;
            if (count >= 1) { break; }
        } while (true);
        result = count;
    }
}
