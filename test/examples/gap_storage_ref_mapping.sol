// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Rejected: a `storage` reference to a mapping or an array
// (`mapping(address => uint256) storage m = balances;`) stops the
// translation of the whole file; references to structs can be read. Gap
// `storage-ref-mapping` in docs/capabilities.toml.
contract GapStorageRefMapping {
    mapping(address => uint256) public balances;

    /// @custom:strata ensures r == balances[k]
    function get(address k) external view returns (uint256 r) {
        mapping(address => uint256) storage m = balances;
        r = m[k];
    }
}
