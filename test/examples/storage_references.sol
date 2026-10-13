// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A storage reference (`Info storage d = data;`) can be read, but writing
// through it is not modelled (the write would not reach the storage), so
// it is rejected rather than verified as if nothing changed.
contract StorageReferences {
    struct Info {
        uint256 value;
        bool flag;
    }
    Info public data;

    function setThrough() public {
        Info storage d = data;
        d.value = 5;
    }
}
