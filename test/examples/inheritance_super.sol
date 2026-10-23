// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// `super.f(…)` runs the implementation of `f` that follows, in the
// linearization of the contract being verified, the contract the call is
// written in: in a function, a modifier or a constructor. `Base.f(…)` runs
// the one `Base` has. A chain has one linearization (Top, Mid, Base), so
// each postcondition below holds wherever its contract is verified.

contract Base {
    uint256 public x;

    // Passes.
    /// @custom:strata ensures x == val + 1
    function setX(uint256 val) public virtual {
        x = val + 1;
    }
}

contract Mid is Base {
    // Passes: Base adds 1 to val + 2.
    /// @custom:strata ensures x == val + 3
    function setX(uint256 val) public virtual override {
        super.setX(val + 2);
    }
}

contract Top is Mid {
    // Passes.
    /// @custom:strata ensures x == val + 3
    function setX(uint256 val) public override {
        super.setX(val);
    }

    // Not proven: in Top, `super.setX` is Mid's, which adds 3.
    /// @custom:strata ensures x == val + 1
    function viaSuper(uint256 val) external {
        super.setX(val);
    }

    // Passes: `Base.setX` is Base's implementation.
    /// @custom:strata ensures x == val + 1
    function viaBase(uint256 val) external {
        Base.setX(val);
    }

    // Not proven: Base's adds 1.
    /// @custom:strata ensures x == val + 3
    function viaBaseWrong(uint256 val) external {
        Base.setX(val);
    }
}

contract Pair {
    uint256 public x;

    /// @custom:strata ensures x == a * 10 + b
    function set(uint256 a, uint256 b) public virtual {
        x = a * 10 + b;
    }
}

contract PairChild is Pair {
    // Passes: named arguments bind by name.
    /// @custom:strata requires a < 10 && b < 10
    /// @custom:strata ensures x == a * 10 + b
    function set(uint256 a, uint256 b) public override {
        super.set({b: b, a: a});
    }
}

contract PairWrong is Pair {
    // Not proven: `a` is the tens.
    /// @custom:strata requires a < 10 && b < 10
    /// @custom:strata ensures x == b * 10 + a
    function set(uint256 a, uint256 b) public override {
        super.set({b: b, a: a});
    }
}

contract Plain {
    uint256 public x;

    /// @custom:strata ensures x == 1
    function f() public virtual {
        x = 1;
    }
}

// Passes: Middle does not override `f`, so its `super.f` is Plain's, the
// one Leaf has too.
contract Middle is Plain {
    /// @custom:strata ensures x == 1
    function g() public {
        super.f();
    }
}

contract Leaf is Middle {}

contract MA {
    uint256 public x;

    /// @custom:strata ensures x == 1
    function f() public virtual {
        x = 1;
    }
}

contract MB is MA {
    /// @custom:strata ensures x == 2
    function f() public virtual override {
        x = 2;
    }

    modifier m() {
        super.f();
        _;
    }
}

contract MC is MB {
    /// @custom:strata ensures x == 3
    function f() public override {
        x = 3;
    }

    // Passes: `m` is written in MB, where `super.f` is MA's.
    /// @custom:strata ensures x == 1
    function g() public m {}

    // Not proven: x is 1.
    /// @custom:strata ensures x == 2
    function h() public m {}
}

contract KA {
    /// @custom:strata ensures r == 1
    function k() internal pure virtual returns (uint256 r) {
        r = 1;
    }
}

contract KB is KA {
    uint256 public x;

    /// @custom:strata ensures r == 2
    function k() internal pure virtual override returns (uint256 r) {
        r = 2;
    }

    constructor() {
        x = super.k();
    }
}

contract KC is KB {
    /// @custom:strata ensures r == 3
    function k() internal pure override returns (uint256 r) {
        r = 3;
    }

    // Passes: KB's constructor is written in KB, where `super.k` is KA's.
    /// @custom:strata ensures x == 1
    constructor() {}
}

contract KCWrong is KB {
    /// @custom:strata ensures r == 3
    function k() internal pure override returns (uint256 r) {
        r = 3;
    }

    // Refuted: x is 1.
    /// @custom:strata ensures x == 2
    constructor() {}
}
