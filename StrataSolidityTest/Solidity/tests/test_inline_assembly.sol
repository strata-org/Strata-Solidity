// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract InlineAssemblyTest {
    uint256 public storedValue;

    function getBalance(address addr) external view returns (uint256 bal) {
        assembly {
            bal := balance(addr)
        }
    }

    function directStore(uint256 slot, uint256 value) external {
        assembly {
            sstore(slot, value)
        }
    }

    function addAssembly(uint256 a, uint256 b) external pure returns (uint256 result) {
        assembly {
            result := add(a, b)
        }
    }
}
