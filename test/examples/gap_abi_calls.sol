// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Not supported: `abi.encodeWithSelector` and `abi.encodeWithSignature`
// with arguments, `abi.encode` with more than 6 arguments and
// `abi.encodePacked` with more than 4 stop the translation of the whole
// file (`abi.decode` too). Gap `abi-functions` in docs/capabilities.toml.
contract GapAbiCalls {
    bytes32 public last;

    function record(address to, uint256 amount) external {
        last = keccak256(abi.encodeWithSelector(bytes4(0xa9059cbb), to, amount));
    }
}
