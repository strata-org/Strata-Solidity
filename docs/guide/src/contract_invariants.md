# Contract Invariants

A contract invariant is a property that must hold at all times — after the constructor completes and on entry and exit of every public/external function.

## Declaring an Invariant

Invariants are placed on **state variable declarations** inside the contract:

```solidity
contract Token {
    mapping(address => uint256) public balances;
    /// @custom:strata invariant totalSupply >= 0
    /// @custom:strata invariant totalSupply == sum(balances)
    uint256 public totalSupply;
}
```

StrataSolidity checks that:
1. The constructor **establishes** the invariant (checked as postcondition).
2. Every public/external function **maintains** the invariant (assumed on entry, checked on exit).
3. Pure and view functions are excluded (they don't modify state).

## The `sum()` Aggregate

`sum(mapping)` represents the sum of all values in a mapping. This is the standard way to express token supply conservation:

```solidity
contract Token {
    mapping(address => uint256) public balances;
    /// @custom:strata invariant totalSupply == sum(balances)
    uint256 public totalSupply;
}
```

The verifier automatically knows that:
- `sum(update(m, k, v)) == sum(m) - m[k] + v`
- When you do `balances[to] += amount`, the sum increases by `amount`
- When you do `balances[from] -= amount`, the sum decreases by `amount`

This is enough for z3 to prove that `mint` (which increases both `totalSupply` and a balance) and `transfer` (which moves between balances without changing the sum) maintain the invariant.

## Constructor Behavior

Constructors **establish** invariants — they must make the invariant true, but they don't assume it was true before (there is no "before" for a constructor):

```solidity
contract Counter {
    /// @custom:strata invariant count >= 0
    uint256 public count;

    constructor() {
        count = 10;  // ✅ establishes count >= 0
    }
}
```

If the constructor set `count` to a value that violates the invariant, verification would fail.

## Example: Supply Cap

```solidity
contract CappedToken {
    mapping(address => uint256) public balances;
    /// @custom:strata invariant totalSupply <= 1000000
    uint256 public totalSupply;

    /**
     * @notice Mints tokens up to the supply cap.
     * @custom:strata requires amount > 0
     * @custom:strata modifies totalSupply, balances[to]
     * @custom:strata ensures totalSupply == old(totalSupply) + amount
     */
    function mint(address to, uint256 amount) external {
        require(totalSupply + amount <= 1000000, "Cap exceeded");
        totalSupply += amount;
        balances[to] += amount;
    }
}
```

## Invariants vs. Postconditions

- **Postconditions** are function-specific: "after `transfer`, the sender's balance decreased by `amount`."
- **Invariants** are contract-wide: "the total supply equals the sum of all balances."

Use invariants for properties that every function must maintain. Use postconditions for properties specific to a single function.

## When Invariants Fail

If an invariant returns ❓ unknown for a specific function, the IDE shows:
- Which functions maintain the invariant (✅)
- Which functions may break it (❌)
- The offending function gets a red marker: `✗ breaks invariant`

Common causes:
- A function modifies the invariant's variable without maintaining the property
- Missing `requires` that would constrain inputs
- The invariant is actually too strong for the contract's logic
