# Annotation Reference

All specifications are written as [NatSpec](https://docs.soliditylang.org/en/latest/natspec-format.html) `@custom:strata` annotations in doc comments. No special imports or stub functions are needed.

## Annotations

| Annotation | Placement | Description |
|---|---|---|
| `@custom:strata requires <expr>` | above function | Precondition — must hold on entry |
| `@custom:strata ensures <expr>` | above function | Postcondition — must hold on exit |
| `@custom:strata invariant <expr>` | on the contract or a state variable | Contract invariant — established by the constructor, maintained by public/external functions, assumed by view functions |
| `@custom:strata modifies <vars>` | above function | Frame condition — only listed state variables may change |
| `@custom:strata loop-invariant <expr>` | above function | Loop invariant — maintained across loop iterations |

## Specification Expressions

Specifications use Solidity expression syntax with these additions:

| Expression | Meaning |
|---|---|
| `old(expr)` | Value of `expr` before function execution |
| `sum(mapping)` | Sum of all values in a mapping (with automatic update axiom) |
| `forall v : T :: expr` | For all values `v` of type `T`, `expr` holds |
| `exists v : T :: expr` | There exists a value `v` of type `T` where `expr` holds |
| `a ==> b` | Implication: if `a` then `b` |
| `type(T).max` / `type(T).min` | Maximum/minimum value of integer type `T` |
| `keccak256(abi.encodePacked(a, b))` | Hash as mapping key |
| `msg.sender` / `msg.value` | Transaction context |
| `address(0)` | Zero address |
| `+`, `-`, `*`, `/`, `%` | Arithmetic (including division and modulo) |

## Modifies Clause

| Pattern | Meaning |
|---|---|
| `modifies balances` | Entire mapping may change |
| `modifies balances[msg.sender]` | Only this key may change; other keys get automatic frame |
| `modifies balances[from], balances[to]` | Multiple keys; combined frame exclusion |
| `modifies balances, totalSupply` | Multiple variables |

State variables NOT listed in `modifies` get automatic frame conditions (their value is preserved).

## Placement Rules

- `requires`, `ensures`, `modifies`, `loop-invariant`: placed above the function they apply to
- `invariant`: placed in the NatSpec above the `contract` keyword or on a **state variable declaration** inside the contract
- Use `@notice` for natural language documentation alongside specs
- Both `///` single-line and `/** */` multi-line comment styles are supported

## Comment Styles

Single-line:
```solidity
/// @notice Mints new tokens to the recipient.
/// @custom:strata modifies balances[to], totalSupply
/// @custom:strata ensures balances[to] == old(balances[to]) + amount
function mint(address to, uint256 amount) external { ... }
```

Multi-line:
```solidity
/**
 * @notice Mints new tokens to the recipient.
 * @custom:strata modifies balances[to], totalSupply
 * @custom:strata ensures balances[to] == old(balances[to]) + amount
 */
function mint(address to, uint256 amount) external { ... }
```

## Automatic Assumptions

The verifier automatically assumes:
- Parameters, state variables (on entry), `msg.sender` and `msg.value` hold
  values of their Solidity types: an unsigned integer is never negative, a
  `uint8` is at most 255, an address fits in 160 bits
- `msg.sender != address(0)` (the zero address cannot send transactions)
- `emit` statements have no verification effect
- `revert` and a failing `require` end the path: postconditions are checked
  only on the paths that do not revert

Never restate these in a specification: `requires amount >= 0` or
`invariant totalSupply >= 0` on a `uint256` is true by its type and adds
nothing.

## Full Example

```solidity
contract Token {
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowance;
    /// @custom:strata invariant totalSupply == sum(balances)
    uint256 public totalSupply;
    uint256 public collectedFees;

    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @notice Transfers tokens from sender to recipient.
     * @custom:strata requires to != msg.sender
     * @custom:strata requires amount <= balances[msg.sender]
     * @custom:strata modifies balances[msg.sender], balances[to]
     * @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
     * @custom:strata ensures balances[to] == old(balances[to]) + amount
     */
    function transfer(address to, uint256 amount) external {
        require(to != msg.sender, "self-transfer");
        require(amount <= balances[msg.sender], "insufficient");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
    }

    /**
     * @notice Mints new tokens to the recipient.
     * @custom:strata modifies balances[to], totalSupply
     * @custom:strata ensures balances[to] == old(balances[to]) + amount
     * @custom:strata ensures totalSupply == old(totalSupply) + amount
     */
    function mint(address to, uint256 amount) external {
        balances[to] += amount;
        totalSupply += amount;
    }

    /**
     * @notice Approves spender to transfer tokens on behalf of sender.
     * @custom:strata modifies allowance[msg.sender]
     * @custom:strata ensures allowance[msg.sender][spender] == amount
     */
    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    /**
     * @notice Calculates fee as a percentage of amount.
     * @custom:strata modifies collectedFees
     * @custom:strata ensures collectedFees == old(collectedFees) + (amount * 3) / 1000
     */
    function collectFee(uint256 amount) external {
        collectedFees += (amount * 3) / 1000;
    }
}
```
