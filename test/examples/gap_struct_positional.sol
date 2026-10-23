// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: a struct built with positional arguments (`Info(1, 2)`)
// stops the translation of the whole file; the named form `Info({a: 1,
// b: 2})` works. Gap `struct-positional` in docs/capabilities.toml.
contract GapStructPositional {
    struct Info { uint256 a; uint256 b; }

    /// @custom:strata ensures r == 3
    function sum() external pure returns (uint256 r) {
        Info memory i = Info(1, 2);
        r = i.a + i.b;
    }
}
