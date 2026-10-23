// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A constant expression has the value solc computes: exactly, with
// rational intermediate values, and with every unit and exponent applied.
// `(7 / 2) * 2` used to be divided step by step in integers (giving 6, so
// `x == 6` was proven), and `2.5 ether` and `1e18` were rejected.
contract ConstantExpressions {
    // Passes: solc evaluates (7 / 2) * 2 exactly, as 7.
    function rational() external pure {
        uint256 x = (7 / 2) * 2;
        assert(x == 7);
    }

    // Refuted: claims step-by-step integer division.
    function rationalWrong() external pure {
        uint256 x = (7 / 2) * 2;
        assert(x == 6);
    }

    // Passes: units and exponents are exact.
    function units() external pure {
        assert(2.5 ether == 2500000000000000000 && 1e18 == 10 ** 18);
    }

    // Refuted: 1.5 gwei is 1500000000 wei.
    function unitsWrong() external pure {
        assert(1.5 gwei == 1500000001);
    }
}
