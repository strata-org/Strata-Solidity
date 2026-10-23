// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Solidity copies a struct into storage, and from storage or calldata into
// memory (in an assignment, a declaration, an argument and a returned
// value); only memory-to-memory assignments share the struct. Structs are
// heap objects in the model, and these assignments used to share them, so
// every false property below but the last was proven.
contract StructCopies {
    struct Info { uint256 value; uint256 other; }
    Info public a;
    Info public b;

    function _bump(Info memory m) internal pure {
        m.value = 9;
    }

    function _get() internal view returns (Info memory) {
        return a;
    }

    // Refuted: `b = a` copies, so writing b leaves a at 1.
    /// @custom:strata requires a.value == 1
    /// @custom:strata ensures a.value == 5
    function storageToStorage() external {
        b = a;
        b.value = 5;
    }

    // Passes.
    /// @custom:strata requires a.value == 1
    /// @custom:strata ensures a.value == 1 && b.value == 5
    function storageToStorageTrue() external {
        b = a;
        b.value = 5;
    }

    // Refuted: `m` is a memory copy of a.
    /// @custom:strata requires a.value == 1
    /// @custom:strata ensures a.value == 9
    function storageToMemory() external {
        Info memory m = a;
        m.value = 9;
    }

    // Passes.
    /// @custom:strata requires a.value == 1
    /// @custom:strata ensures a.value == 1
    function storageToMemoryTrue() external {
        Info memory m = a;
        m.value = 9;
    }

    // Refuted: `a = m` copies m into storage; writing m afterwards leaves a.
    /// @custom:strata requires b.value == 1
    /// @custom:strata ensures a.value == 7
    function memoryToStorage() external {
        Info memory m = b;
        a = m;
        m.value = 7;
    }

    // Passes.
    /// @custom:strata requires b.value == 1
    /// @custom:strata ensures a.value == 1
    function memoryToStorageTrue() external {
        Info memory m = b;
        a = m;
        m.value = 7;
    }

    // Refuted: `m` is a memory copy of the calldata struct.
    function calldataToMemory(Info calldata c) external pure {
        Info memory m = c;
        m.value = c.value + 1;
        assert(m.value == c.value);
    }

    // Passes.
    function calldataToMemoryTrue(Info calldata c) external pure {
        Info memory m = c;
        m.value = c.value + 1;
        assert(m.value != c.value);
    }

    // Passes: `_bump` gets a memory copy of a.
    /// @custom:strata requires a.value == 1
    /// @custom:strata ensures a.value == 1
    function argumentCopied() external {
        _bump(a);
    }

    // Not proven: a memory struct is passed by reference, so `_bump`
    // sets m.value to 9.
    /// @custom:strata requires a.value == 1
    function argumentShared() external view {
        Info memory m = a;
        _bump(m);
        assert(m.value == 1);
    }

    // Not proven: `_get` returns a memory copy of a, so a stays 1.
    /// @custom:strata requires a.value == 1
    /// @custom:strata ensures a.value == 9
    function returnedCopy() external {
        Info memory m = _get();
        m.value = 9;
    }
}
