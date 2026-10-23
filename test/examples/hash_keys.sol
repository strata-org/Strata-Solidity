// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// `keccak256`, `sha256`, `abi.encode` and `abi.encodePacked` are
// uninterpreted functions: equal arguments give equal results, and nothing
// else is known about the results (two different arguments may even give
// the same hash). A hash of the parameters works as a mapping key in code
// and in specifications.
contract HashKeys {
    mapping(bytes32 => uint256) public data;

    // Passes: the key in the specification is the key the code writes.
    /// @custom:strata modifies data[keccak256(abi.encodePacked(a, b))]
    /// @custom:strata ensures data[keccak256(abi.encodePacked(a, b))] == v
    function set(uint256 a, address b, uint256 v) external {
        data[keccak256(abi.encodePacked(a, b))] = v;
    }

    // Passes: `abi.encode` with several arguments, and `sha256`.
    /// @custom:strata ensures data[sha256(abi.encode(a, b, c))] == 1
    function mark(uint256 a, uint256 b, address c) external {
        data[sha256(abi.encode(a, b, c))] = 1;
    }

    // Refuted: `abi.encode` and `abi.encodePacked` are different functions,
    // so this key need not be the one written.
    /// @custom:strata ensures data[keccak256(abi.encode(a, b))] == v
    function setOtherKey(uint256 a, address b, uint256 v) external {
        data[keccak256(abi.encodePacked(a, b))] = v;
    }

    // Refuted: nothing excludes a collision of the two hashes, so writing
    // one key may change the other.
    /// @custom:strata requires a != b
    /// @custom:strata ensures data[keccak256(abi.encode(b))] == old(data[keccak256(abi.encode(b))])
    function setOne(uint256 a, uint256 b) external {
        data[keccak256(abi.encode(a))] = 1;
    }
}
