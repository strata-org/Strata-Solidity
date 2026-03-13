// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract AssemblyTest {
    uint256 public value;
    mapping(address => uint256) public balances;

    function useAssembly() public {
        value = 42;
        assembly {
            sstore(0, 99)
        }
        // After assembly, value and balances are havoced
        assert(value == 42); // should be unprovable after havoc
    }
}
