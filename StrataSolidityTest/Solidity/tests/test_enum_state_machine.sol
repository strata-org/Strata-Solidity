// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Enum state machine with transition specs.
contract EnumStateMachine {

    enum State { Created, Active, Inactive }

    State public state;

    constructor() {
        state = State.Created;
    }

    /// @custom:strata requires state == 0
    /// @custom:strata ensures state == 1
    function activate() external {
        require(state == State.Created);
        state = State.Active;
    }

    /// @custom:strata requires state == 1
    /// @custom:strata ensures state == 2
    function deactivate() external {
        require(state == State.Active);
        state = State.Inactive;
    }
}
