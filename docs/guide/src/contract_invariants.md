# Contract Invariants

A contract invariant is a property that must hold at all times — after the constructor completes and on entry and exit of every public/external function.

## Declaring an Invariant

Invariants go in the NatSpec of the contract itself or of one of its state
variables; both placements mean the same thing:

```solidity
/// @custom:strata invariant totalSupply == sum(balances)
contract Token {
    mapping(address => uint256) public balances;
    /// @custom:strata invariant totalSupply <= 1000000
    uint256 public totalSupply;
}
```

solc attaches each NatSpec block to exactly one declaration, so every
contract in a file has its own invariants. An invariant on an interface or a
library (which have no state) is reported as having no effect.

An invariant is a single-state property about contract state: it may use
state variables, named constants, `sum(...)` and quantifiers, but not
`old(...)` (use `ensures` for two-state properties). A function parameter
that shadows a state variable does not capture an invariant.

StrataSolidity checks that:
1. The constructor **establishes** the invariant (checked as postcondition).
   State-variable initializers (`uint256 cap = 1000;`) run before the
   constructor body. A contract without a constructor gets an implicit empty
   one, so the deployment state must satisfy the invariant too.
2. Every public/external function, `receive` and `fallback` **maintains** the
   invariant (assumed on entry, checked on exit).
3. View functions may **rely** on the invariant (assumed on entry); they
   cannot break it, so nothing is checked on exit. Pure functions do neither.
4. Internal and private functions neither assume nor re-establish it: they run
   in the middle of an entry point, where the invariant may be temporarily
   broken. The entry point that calls them checks it on exit.
5. In an external function, the invariant holds **before each external
   call** that may re-enter the contract (see below).

## External calls and reentrancy

Code outside the contract is not interpreted. A call that runs it may call
back into the contract (re-enter it) and change its state through its
external functions, so the state is unknown after the call:

| Call | State after the call |
|---|---|
| A mutating function of another contract (through an interface, a contract-typed variable or an external function value), `this.f()`, `addr.call(…)`, `new C(…)` | Unknown, except that the invariants hold |
| A `view` or `pure` function, `addr.staticcall(…)`, `send`, `transfer` | Unchanged |
| `addr.delegatecall(…)` | Unknown, invariants included |

The contract's external functions maintain its invariants, so the
invariants still hold after a re-entrant call, provided they held when the
contract was re-entered: an external function checks them before each such
call (`invariant … holds before the external call`) and assumes them after
it. This is the checks-effects-interactions discipline: finish updating
state, so that the invariants hold again, before calling out.

```solidity
/// @custom:strata invariant fee <= 100
contract Bank {
    IToken token;
    uint256 fee;

    /// @custom:strata ensures fee <= 100      // ✅ the invariant holds after the call
    /// @custom:strata ensures fee == old(fee) // ❌ a re-entrant call may change fee
    function pay(address to, uint256 amount) external {
        require(token.transfer(to, amount));
    }

    function unsafePay(address to) external {
        fee = 200;
        require(token.transfer(to, 1));        // ❌ the invariant does not hold here
        fee = 50;
    }
}
```

A constructor's calls cannot re-enter (the contract has no code yet), and a
`try` whose call reverts leaves the state as it was before the call. Values
returned by external calls are unknown values of their type. `immutable`
variables never change.

`--assume-no-reentrancy` trusts that no call re-enters the contract: calls
other than `delegatecall` then leave its state unchanged, and the
invariants need not hold at a call. Results obtained with it hold only if
that is true, for example because every function that changes state is
guarded by a reentrancy lock.

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

Constructors **establish** invariants — they must make the invariant true, but they don't assume it was true before (there is no "before" for a constructor). Mappings start empty, so `sum(m)` is 0 at the start of a constructor:

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
