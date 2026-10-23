// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// An invariant must hold between transactions, whoever calls next, so it
// may not mention the caller (or, like block values, anything else that
// belongs to one transaction). This one would be established for the
// deployer and assumed for every later caller: with `owner == msg.sender`
// assumed on entry, `require(msg.sender != owner)` could never pass, and
// the false `ensures x == 7` below would be proven. The file is rejected.
contract InvariantMsgSender {
    /// @custom:strata invariant owner == msg.sender
    address public owner;
    uint256 public x;

    constructor() {
        owner = msg.sender;
    }

    /// @custom:strata ensures x == 7
    function anyoneCanCall() external {
        require(msg.sender != owner);
        x = 1;
    }
}
