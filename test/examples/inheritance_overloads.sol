// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// An override has the parameter types of the function it replaces; a
// function of the same name with other parameters is an overload, and the
// inherited function stays a function of the derived contract. (Overloads
// whose parameters are all integers or addresses, `f(uint256)` and
// `f(address)`, have the same parameter types in the verifier and are
// rejected, in one contract too.)

contract Base {
    // Passes, also in Derived, where it is inherited.
    /// @custom:strata ensures r == a
    function f(uint256 a) public pure virtual returns (uint256 r) {
        r = a;
    }

    // Refuted, also in Derived.
    /// @custom:strata ensures r == a + 1
    function g(uint256 a) public pure returns (uint256 r) {
        r = a;
    }
}

contract Derived is Base {
    // Passes: an overload of `f`, not an override.
    /// @custom:strata ensures r == !a
    function f(bool a) public pure returns (bool r) {
        r = !a;
    }

    // Passes: an overload of the inherited `g`.
    /// @custom:strata ensures r == a + b
    function g(uint256 a, uint256 b) public pure returns (uint256 r) {
        r = a + b;
    }
}
