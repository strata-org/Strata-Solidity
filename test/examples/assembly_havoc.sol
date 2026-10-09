// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Inline assembly is not interpreted. Whatever a block may write is
// unknown afterwards: every Solidity local, parameter or return variable
// it assigns (`x := …`), every variable in memory if it writes memory, and
// all of the contract's state if it may write storage (solc rejects that
// in `view` and `pure` functions). A block that may end the function
// (`return`, `stop`) does so on some paths, with unknown return values.
contract AssemblyHavoc {
    struct Info { uint256 value; }

    uint256 public stored;
    mapping(address => uint256) public balances;
    Info internal info;
    uint8 public small;

    // Fails: the constructor's block may write `stored`.
    /// @custom:strata ensures stored == 0
    constructor() {
        assembly { sstore(stored.slot, 5) }
    }

    // Fails: `t` is reassigned in the block.
    /// @custom:strata ensures r == 5
    function localAssigned(uint256 a) external pure returns (uint256 r) {
        uint256 t = 5;
        assembly { t := a }
        r = t;
    }

    // Fails: the named return is reassigned in the block.
    /// @custom:strata ensures r == 7
    function returnAssigned() external view returns (uint256 r) {
        r = 7;
        assembly { r := sload(stored.slot) }
    }

    // Fails: the parameter is reassigned in the block.
    /// @custom:strata ensures r == x
    function parameterAssigned(uint256 x) external pure returns (uint256 r) {
        assembly { x := add(x, 1) }
        r = x;
    }

    // Passes: the block assigns only `y` and a Yul local.
    /// @custom:strata ensures r == x
    function otherAssigned(uint256 x) external pure returns (uint256 r) {
        r = x;
        uint256 y;
        assembly {
            let tmp := add(x, 1)
            y := tmp
        }
    }

    // Fails: two blocks give independent values.
    /// @custom:strata ensures a == b
    function twoBlocks() external view returns (uint256 a, uint256 b) {
        assembly { a := gas() }
        assembly { b := gas() }
    }

    // Passes: a view function's assembly cannot write state.
    /// @custom:strata ensures r == balances[who]
    function viewKeepsState(address who) external view returns (uint256 r) {
        r = balances[who];
        assembly { let z := sload(0) }
    }

    // Fails: the block may write any state variable.
    /// @custom:strata ensures balances[who] == old(balances[who])
    function mutatingHavocsState(address who) external {
        assembly { sstore(0, 1) }
    }

    // Fails: the block may write the storage `d` refers to.
    /// @custom:strata ensures ok
    function storageReference() external returns (bool ok) {
        Info storage d = info;
        uint256 before = d.value;
        assembly { sstore(0, 1) }
        ok = d.value == before;
    }

    // Passes: whatever the block writes, `small` reads as a uint8.
    /// @custom:strata ensures small <= 255
    function keepsTypes() external {
        assembly { sstore(small.slot, 1000) }
    }

    // Passes: reading storage writes nothing.
    /// @custom:strata ensures stored == old(stored)
    function readsStorage() external {
        assembly { let z := sload(0) }
    }

    // Passes: hashing through scratch memory leaves `r` alone.
    /// @custom:strata ensures r == x
    function hashes(uint256 x) external pure returns (uint256 r) {
        r = x;
        bytes32 h;
        assembly {
            mstore(0, x)
            h := keccak256(0, 32)
        }
    }

    // Fails: the block may write the array's elements.
    /// @custom:strata ensures ok
    function writesMemory(uint256[] memory arr) external pure returns (bool ok) {
        require(arr.length > 0);
        arr[0] = 5;
        assembly { mstore(add(arr, 32), 7) }
        ok = arr[0] == 5;
    }

    // Fails: the array now points elsewhere, with another length.
    /// @custom:strata ensures ok
    function repoints(uint256[] memory arr) external pure returns (bool ok) {
        require(arr.length == 1);
        assembly { arr := 0x60 }
        ok = arr.length == 1;
    }

    // Fails: the block returns 8.
    /// @custom:strata ensures r == 7
    function returnsEarly() external pure returns (uint256 r) {
        r = 7;
        assembly {
            mstore(0, 8)
            return(0, 32)
        }
    }

    // Fails: the block stops before the write.
    /// @custom:strata ensures balances[who] == 1
    function stops(address who) external {
        assembly { stop() }
        balances[who] = 1;
    }
}
