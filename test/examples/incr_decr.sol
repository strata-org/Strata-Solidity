// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// `i++` yields the old value and `++i` the new one; `++` on a mapping
// element writes through, evaluating its index once.
contract IncrDecr {
    mapping(uint256 => uint256) public counts;

    /// @custom:strata ensures x == j && y == j + 2
    function values(uint256 j) external pure returns (uint256 x, uint256 y) {
        uint256 k = j;
        x = k++;
        y = ++k;
    }

    /// @custom:strata ensures counts[who] == old(counts[who]) + 1
    function bump(uint256 who) external {
        counts[who]++;
    }

    /// @custom:strata ensures a == old(counts[w]) && b == old(counts[w]) + 2
    function elementValues(uint256 w) external returns (uint256 a, uint256 b) {
        a = counts[w]++;
        b = ++counts[w];
    }

    // Refuted: `k++` runs once, so only counts[0] changes.
    /// @custom:strata ensures counts[1] == old(counts[1]) + 1
    function indexOnce() external {
        uint256 k = 0;
        counts[k++]++;
    }

    // Refuted: the condition, `k++` included, runs before every iteration.
    function inCondition() external pure {
        uint256 k = 0;
        while (k++ < 3) {
        }
        assert(k == 0);
    }
}
