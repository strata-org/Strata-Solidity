// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A quantified variable ranges over the values of its declared type, not
// over all integers: `exists i : uint8 :: P` needs a witness between 0 and
// 255, and `forall v : uint8 :: P` is about those values only. (Whether z3
// finds the witness of a true existential, or refutes `exists i : uint8 ::
// i == k` for a large `k`, depends on its version, so no such property is
// pinned here.)
contract QuantifierTypes {
    uint256 public last;

    // Refuted: no uint8 exceeds 255.
    /// @custom:strata ensures exists i : uint8 :: i > 255
    function bigByte() external {
        last = 0;
    }

    // Refuted: no address exceeds 2^160 - 1.
    /// @custom:strata ensures exists a : address :: a > type(uint160).max
    function bigAddress() external {
        last = 0;
    }

    // Refuted: no uint256 is negative.
    /// @custom:strata ensures exists v : uint256 :: v < 0
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

// A true existential whose witness z3 finds (here through the mapping write,
// with z3 4.8.12 and 4.15). z3 does not search for witnesses in general: the
// equally true `exists n : uint256 :: n > 5` is unknown.
contract ExistsWitness {
    mapping(address => uint256) public balances;

    // Passes: `to` is a witness.
    /// @custom:strata ensures exists a : address :: balances[a] == v
    function set(address to, uint256 v) external {
        balances[to] = v;
    }
}
