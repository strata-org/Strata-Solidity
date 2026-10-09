// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A loop condition is evaluated before every iteration, including any call,
// assignment or division it makes, and a for-loop variable shadows a state
// variable of the same name inside the loop.
contract LoopConditions {
    uint256 public i;

    /// @custom:strata ensures r == (x < 3)
    function small(uint256 x) public pure returns (bool r) {
        r = x < 3;
    }

    // Refuted: the loop runs while small(k) holds, so k ends at 3.
    function countWrong() external pure {
        uint256 k = 0;
        while (small(k)) {
            k++;
        }
        assert(k == 0);
    }

    // Refuted: the assignment in the condition runs at every iteration,
    // so x ends at 0.
    function assignWrong() external pure {
        uint256 x = 3;
        while ((x = x - 1) > 0) {
        }
        assert(x == 2);
    }

    // Refuted: the division is evaluated at every iteration (and checked
    // each time), so a ends below d.
    function divideWrong(uint256 a) external pure {
        uint256 d = 2;
        while (a / d > 0) {
            a = a / d;
        }
        assert(a >= d);
    }

    // The loop variable `i` is not the state variable `i`.
    /// @custom:strata ensures i == old(i)
    function loopLocal() external {
        for (uint256 i = 0; i < 3; i++) {
        }
    }
}
