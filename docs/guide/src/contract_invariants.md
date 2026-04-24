# Contract Invariants

A contract invariant is a property that must hold at all times — after the constructor completes and on entry and exit of every public/external function. Invariants capture global properties of your contract's state.

## Declaring an invariant

Invariants are declared at the contract level:

```solidity
/// @custom:strata invariant totalSupply <= type(uint256).max
contract SafeToken {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;
    // ...
}
```

StrataSolidity checks that:
1. The invariant holds after the constructor completes.
2. Assuming the invariant holds on entry to any public/external function, it still holds on exit.

## Example: token with supply cap

```solidity
/// @custom:strata invariant totalSupply <= 1000000
contract CappedToken {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    /// @custom:strata requires amount > 0
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    /// @custom:strata modifies totalSupply, balances[to]
    function mint(address to, uint256 amount) external {
        require(totalSupply + amount <= 1000000, "Cap exceeded");
        totalSupply += amount;
        balances[to] += amount;
    }
}
```

If `mint` could ever push `totalSupply` above 1,000,000, StrataSolidity would report a verification failure on the invariant.

## Invariants vs. postconditions

- **Postconditions** are function-specific: "after `transfer`, the sender's balance decreased by `amount`."
- **Invariants** are contract-wide: "the total supply never exceeds the cap."

Use invariants for properties that every function must maintain. Use postconditions for properties specific to a single function's behavior.

## Multiple invariants

You can declare multiple invariants on a contract:

```solidity
/// @custom:strata invariant totalSupply >= 0
/// @custom:strata invariant totalSupply <= 1000000
contract Token {
    // ...
}
```

All invariants are checked independently.
