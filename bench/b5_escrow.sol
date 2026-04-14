// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Bench 5: State machine with enum, multiple transitions, 6 functions
contract B5_Escrow {
    enum State { Created, Funded, Shipped, Completed, Refunded }

    address public buyer;
    address public seller;
    uint256 public price;
    State public state;
    uint256 public fundedAt;

    /// @custom:strata requires msg.sender == buyer
    /// @custom:strata requires state == 0
    /// @custom:strata requires msg.value == price
    /// @custom:strata ensures state == 1
    /// @custom:strata ensures fundedAt > 0
    function fund() external payable {
        require(msg.sender == buyer, "not buyer");
        require(state == State.Created, "wrong state");
        require(msg.value == price, "wrong amount");
        state = State.Funded;
        fundedAt = block.timestamp;
    }

    /// @custom:strata requires msg.sender == seller
    /// @custom:strata requires state == 1
    /// @custom:strata ensures state == 2
    function ship() external {
        require(msg.sender == seller, "not seller");
        require(state == State.Funded, "wrong state");
        state = State.Shipped;
    }

    /// @custom:strata requires msg.sender == buyer
    /// @custom:strata requires state == 2
    /// @custom:strata ensures state == 3
    function confirm() external {
        require(msg.sender == buyer, "not buyer");
        require(state == State.Shipped, "wrong state");
        state = State.Completed;
    }

    /// @custom:strata requires msg.sender == buyer
    /// @custom:strata requires state == 1
    /// @custom:strata ensures state == 4
    function refund() external {
        require(msg.sender == buyer, "not buyer");
        require(state == State.Funded, "wrong state");
        state = State.Refunded;
    }
}
