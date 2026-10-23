// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// `msg.value` belongs to one transaction, like `msg.sender`: an invariant
// over it would be established with the deployment's value and assumed with
// every later call's. The file is rejected.
contract InvariantMsgValue {
    /// @custom:strata invariant paid == msg.value
    uint256 public paid;

    constructor() payable {
        paid = msg.value;
    }

    /// @custom:strata ensures r
    function check() external payable returns (bool r) {
        r = (msg.value == paid);
    }
}
