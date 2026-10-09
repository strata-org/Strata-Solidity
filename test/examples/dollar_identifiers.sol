// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Solidity identifiers may start with `$` (OpenZeppelin v5 names its
// ERC-7201 storage pointer `$`). Laurel reserves a leading `$` for
// generated names, so the frontend renames them consistently in the AST
// and in specs.
contract Dollar {
    uint256 public $total;
    mapping(address => uint256) public $bal;
    /// @custom:strata modifies $total, $bal[to]
    /// @custom:strata ensures $total == old($total) + $a
    /// @custom:strata ensures $bal[to] == old($bal[to]) + $a
    function add(address to, uint256 $a) external {
        uint256 $tmp = $a;
        $total += $tmp;
        $bal[to] += $tmp;
    }
}
