// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: UserDefinedTypeName in a local variable declaration.
/// Exercises translateTypeNode's UserDefinedTypeName branch end-to-end.
contract TestStructLocalVar {
    struct Pair {
        uint256 a;
        uint256 b;
    }

    function usePair(uint256 x) public pure returns (uint256) {
        Pair memory p;
        assert(x >= 0);
        return x;
    }
}
