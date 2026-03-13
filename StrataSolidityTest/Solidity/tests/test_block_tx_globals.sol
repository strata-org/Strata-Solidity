// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Test: block and transaction global variables.
contract BlockTxGlobalsTest {
    function useBlockGlobals() public view returns (uint256) {
        uint256 ts = block.timestamp;
        uint256 num = block.number;
        assert(ts >= 0);
        assert(num >= 0);
        return ts + num;
    }

    function useTxOrigin() public view returns (address) {
        address origin = tx.origin;
        return origin;
    }

    function useGasleft() public view returns (uint256) {
        uint256 gas = gasleft();
        assert(gas >= 0);
        return gas;
    }
}
