// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Facts Solidity guarantees that the translator does not assume. Each
// property below is true, but is reported as failed with a counterexample
// the EVM cannot produce, so a proof that depends on it is not found.
// Nothing false is proven: leaving out an assumption only adds behaviors.
contract IncompleteAssumptions {
    enum State { Idle, Running, Done }

    State public state;
    uint256[] public items;
    uint256 public x;

    // Fails (spurious): an enum value is one of its members, but the
    // translator does not constrain enum values.
    /// @custom:strata ensures inRange
    function enumInRange() external view returns (bool inRange) {
        inRange = uint8(state) <= 2;
    }

    // Fails (spurious): `items[i]` reverts unless `i < items.length`, but an
    // index out of range is not modelled as a revert.
    /// @custom:strata ensures i < items.length
    function indexInRange(uint256 i) external view returns (uint256 r) {
        r = items[i];
    }

    // Fails (spurious): a function that is not `payable` reverts when sent
    // Ether, but `msg.value == 0` is not assumed in it.
    /// @custom:strata ensures msg.value == 0
    function notPayable() external {
        x = 1;
    }
}
