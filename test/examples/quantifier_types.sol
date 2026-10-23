// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A quantified variable ranges over the values of its declared type, not
// over all integers: `exists i : uint8 :: P` needs a witness between 0 and
// 255, and `forall v : uint8 :: P` is about those values only.
contract QuantifierTypes {
    uint256 public last;

    // Refuted: for k = 300 no uint8 equals k.
    /// @custom:strata ensures exists i : uint8 :: i == k
    function anyByte(uint256 k) external {
        last = k;
    }

    // Passes: a byte-sized k has a uint8 witness.
    /// @custom:strata requires k <= 255
    /// @custom:strata ensures exists i : uint8 :: i == k
    function aByte(uint256 k) external {
        last = k;
    }

    // Refuted: no address exceeds 2^160 - 1.
    /// @custom:strata ensures exists a : address :: a > type(uint160).max
    function bigAddress() external {
        last = 0;
    }

    // Refuted: no uint256 is -1 (v + 1 == 0 has no non-negative solution).
    /// @custom:strata ensures exists v : uint256 :: v + 1 == 0
    function negativeWitness() external {
        last = 0;
    }

    // Passes: every uint8 is at most 255.
    /// @custom:strata ensures forall v : uint8 :: v <= 255
    function bytesAreSmall() external {
        last = 0;
    }

    // Passes: every int8 is at least -128.
    /// @custom:strata ensures forall v : int8 :: v >= -128
    function signedBytesAreBounded() external {
        last = 0;
    }

    // Refuted: not every uint8 is below 255.
    /// @custom:strata ensures forall v : uint8 :: v < 255
    function notAllBelow255() external {
        last = 0;
    }
}
