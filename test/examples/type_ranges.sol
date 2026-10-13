// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOracle {
    function price() external returns (uint256);
}

// Values carry the ranges of their Solidity types: parameters, state
// variables, `try` return values and hash results. Signed state is not
// assumed to be non-negative.
contract TypeRanges {
    uint256 public total;
    int256 public tick;
    uint8 public small;
    uint256 public last;

    /// @custom:strata ensures total <= type(uint256).max
    function set(uint256 v) external {
        total = v;
    }

    /// @custom:strata ensures small <= 255
    function setSmall(uint8 s) external {
        small = s;
    }

    function setTick(int256 t) external {
        tick = t;
    }

    // `tick` may be negative (setTick(-5)): this must not verify.
    /// @custom:strata ensures tick >= 0
    function stepTick() external {
        tick = tick;
    }

    /// @custom:strata ensures last >= 0
    function poll(address oracle) external {
        try IOracle(oracle).price() returns (uint256 p) {
            last = p;
        } catch {
            last = 0;
        }
    }

    /// @custom:strata ensures r >= 0
    function hashOf(uint256 x) external pure returns (uint256 r) {
        r = uint256(keccak256(abi.encode(x)));
    }
}
