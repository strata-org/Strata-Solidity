// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: UserDefinedTypeName used in local variable declarations.
/// Exercises the parser's UserDefinedTypeName + IdentifierPath handling.
contract TestStructVarDecl {
    struct Pair {
        uint256 a;
        uint256 b;
    }

    struct Triple {
        uint256 x;
        uint256 y;
        uint256 z;
    }

    function checkAdd(uint256 p, uint256 q) public pure returns (uint256) {
        uint256 sum = p + q;
        assert(sum >= p);
        return sum;
    }
}
