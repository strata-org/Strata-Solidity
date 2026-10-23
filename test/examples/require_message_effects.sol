// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// Every argument of `require` is evaluated, even when the condition holds
// ("require arguments are evaluated unconditionally", Solidity docs). So
// the message's effects happen on the passing path too: `_note()` below
// runs on every call, whether the message is a string or a custom error.
contract RequireMessageEffects {
    uint256 public notes;

    error Rejected(uint256 count);

    /// @custom:strata ensures notes == old(notes) + 1
    /// @custom:strata ensures r == notes
    function _note() internal returns (uint256 r) {
        notes += 1;
        r = notes;
    }

    // Passes: the string message's call runs although the check passes.
    /// @custom:strata ensures notes == old(notes) + 1
    function withString() external {
        require(true, _note() == 1 ? "first" : "later");
    }

    // Not proven: claims the message did not run.
    /// @custom:strata ensures notes == old(notes)
    function withStringWrong() external {
        require(true, _note() == 1 ? "first" : "later");
    }

    // Passes: a custom error's arguments are evaluated too.
    /// @custom:strata ensures notes == old(notes) + 1
    function withError() external {
        require(true, Rejected(_note()));
    }

    // Not proven: claims the custom error's argument did not run.
    /// @custom:strata ensures notes == old(notes)
    function withErrorWrong() external {
        require(true, Rejected(_note()));
    }

    // Passes: a message without effects changes nothing.
    /// @custom:strata ensures notes == old(notes)
    function plainMessage(uint256 a) external view {
        require(a > 0, "a is zero");
    }
}
