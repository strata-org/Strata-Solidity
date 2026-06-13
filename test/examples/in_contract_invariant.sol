// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Regression fixture for the in-contract invariant path (R1).
// The invariant is attached to the state variable's NatSpec (INSIDE the
// contract), so it is collected by ContractTranslator and enforced as a
// postcondition on every non-pure function. Previously this emitted an
// unresolved `__strata_invariant` StaticCall and crashed Laurel->Core.
contract InContractInvariant {
    mapping(address => uint256) public balances;

    /// @custom:strata invariant totalSupply == sum(balances)
    uint256 public totalSupply;

    /// @custom:strata modifies balances[to], totalSupply
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    function mint(address to, uint256 amount) external {
        balances[to] += amount;
        totalSupply += amount;
    }

    /// @custom:strata requires from != to
    /// @custom:strata requires amount <= balances[from]
    /// @custom:strata modifies balances[from], balances[to]
    /// @custom:strata ensures balances[from] == old(balances[from]) - amount
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    function transfer(address from, address to, uint256 amount) external {
        require(from != to);
        require(amount <= balances[from]);
        balances[from] -= amount;
        balances[to] += amount;
    }
}
