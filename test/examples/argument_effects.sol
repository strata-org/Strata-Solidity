// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Events, Ether transfers and low-level calls are not modelled, but their
// arguments still run: an argument that changes state does so.
contract ArgumentEffects {
    mapping(uint256 => uint256) public counts;
    event Bumped(uint256 n);

    /// @custom:strata ensures counts[0] == old(counts[0]) + 1
    /// @custom:strata ensures r == 1
    function _bump() internal returns (uint256 r) {
        counts[0] += 1;
        r = 1;
    }

    // Refuted: the event's argument calls `_bump`.
    /// @custom:strata ensures counts[0] == old(counts[0])
    function emits() external {
        emit Bumped(_bump());
    }

    // Refuted: the transfer's argument calls `_bump`.
    /// @custom:strata ensures counts[0] == old(counts[0])
    function pays(address payable to) external {
        to.transfer(_bump());
    }

    // Refuted: so does the call's argument; its result is unknown.
    /// @custom:strata ensures counts[0] == old(counts[0])
    function calls(address to) external {
        (bool ok, ) = to.call(abi.encode(_bump()));
    }

    /// @custom:strata ensures counts[0] == old(counts[0]) + 1
    function emitsOnce() external {
        emit Bumped(_bump());
    }
}
