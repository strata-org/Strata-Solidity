// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Deploying a contract runs its bases' constructors first, most base first,
// after the state-variable initializers. Each runs with its own modifiers,
// before the derived constructor's modifiers, and a `return` in it ends
// only that constructor. Its arguments are those the derived constructor
// gives (`constructor() Base(7)`); those of an inheritance specifier
// (`is Base(7)`) are not read, so the parameters are unknown values.

contract Owned {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
}

// Owned's constructor runs before `onlyOwner`, so the require passes.
contract Vault is Owned {
    uint256 public total;

    // Passes.
    /// @custom:strata ensures owner == msg.sender && total == 1
    constructor() onlyOwner {
        total = 1;
    }
}

contract VaultWrong is Owned {
    uint256 public total;

    // Refuted: the body runs, so total is 1.
    /// @custom:strata ensures total == 0
    constructor() onlyOwner {
        total = 1;
    }
}

contract Counted {
    uint256 public x;

    modifier setsX() {
        x = 5;
        _;
    }

    constructor() setsX {
        uint256 t = 1;
        if (t == 1) {
            return;
        }
        x = 9;
    }
}

// Counted's modifier sets x to 5; its `return` skips `x = 9` but not the
// rest of the deployment. Its local `t` is not this constructor's `t`.
contract Recount is Counted {
    uint256 public y;

    // Passes.
    /// @custom:strata ensures x == 6 && y == 2
    constructor() {
        uint256 t = 2;
        y = t;
        x = x + 1;
    }
}

contract RecountWrong is Counted {
    uint256 public y;

    // Refuted: x is 6.
    /// @custom:strata ensures x == 9
    constructor() {
        uint256 t = 2;
        y = t;
        x = x + 1;
    }
}

contract Priced {
    uint256 public price;

    constructor(uint256 p) {
        price = p;
    }
}

contract Doubled is Priced {
    // Passes: Priced's parameter is 2 * q.
    /// @custom:strata requires q < 1000
    /// @custom:strata ensures price == 2 * q
    constructor(uint256 q) Priced(q * 2) {}
}

contract Halved is Priced {
    // Refuted: price is 2 * q.
    /// @custom:strata requires q < 1000
    /// @custom:strata ensures price == q
    constructor(uint256 q) Priced(q * 2) {}
}

contract Middle is Priced {
    constructor(uint256 q) Priced(q + 1) {}
}

contract Top is Middle {
    // Passes: Middle's parameter is 4, so Priced's is 5.
    /// @custom:strata ensures price == 5
    constructor() Middle(4) {}
}

contract TopWrong is Middle {
    // Refuted: price is 5.
    /// @custom:strata ensures price == 4
    constructor() Middle(4) {}
}

contract Fixed is Priced(7) {
    // Fails: the specifier's argument is not read, so price is any uint256
    // value (it is 7).
    /// @custom:strata ensures price == 7
    constructor() {}
}

contract FixedTrue is Priced(7) {
    // Passes: whatever the argument, price holds a uint256.
    /// @custom:strata ensures price <= type(uint256).max
    constructor() {}
}
