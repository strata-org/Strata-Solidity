// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

type Wei is uint256;
type Seconds is uint256;

contract ModernTypes {
    Wei public totalDeposited;
    mapping(address account => Wei balance) public deposits;

    function deposit() external payable {
        Wei amount = Wei.wrap(msg.value);
        deposits[msg.sender] = Wei.wrap(Wei.unwrap(deposits[msg.sender]) + Wei.unwrap(amount));
        totalDeposited = Wei.wrap(Wei.unwrap(totalDeposited) + Wei.unwrap(amount));
    }

    function getBalance(address account) external view returns (Wei) {
        return deposits[account];
    }

    function callbackType() external pure returns (function(uint256) external returns (uint256)) {
        revert("not implemented");
    }
}
