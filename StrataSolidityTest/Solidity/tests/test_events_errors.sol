// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract EventsAndErrors {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Mint(address indexed to, uint256 amount);

    error InsufficientBalance(uint256 available, uint256 required);
    error ZeroAddress();

    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    /// @custom:strata requires amount > 0
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    function mint(address to, uint256 amount) external {
        require(amount > 0);
        totalSupply += amount;
        balances[to] += amount;
        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    /// @custom:strata requires balances[msg.sender] >= amount
    function transfer(address to, uint256 amount) external {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        if (balances[msg.sender] < amount) {
            revert InsufficientBalance(balances[msg.sender], amount);
        }
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
    }
}
