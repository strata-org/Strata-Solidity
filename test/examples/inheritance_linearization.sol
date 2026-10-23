// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Base constructors run in the reverse of solc's C3 linearization. Here
// L(Z) = Z, K2, K1, A, B, Root, so they run Root, B, A, K1, K2: x is
// (1 * 2) + 1. A depth-first order of the base lists (Root, A, K1, B, K2)
// would give (1 + 1) * 2.

contract Root {
    uint256 public x;

    constructor() {
        x = 1;
    }
}

contract A is Root {
    constructor() {
        x = x + 1;
    }
}

contract B is Root {
    constructor() {
        x = x * 2;
    }
}

contract K1 is A {}

contract K2 is B, A {}

contract Z is K1, K2 {
    // Passes.
    /// @custom:strata ensures x == 3
    constructor() {}
}

contract ZWrong is K1, K2 {
    // Refuted: x is 3.
    /// @custom:strata ensures x == 4
    constructor() {}
}
