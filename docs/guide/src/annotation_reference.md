# Annotation Reference

All specifications are written as [NatSpec](https://docs.soliditylang.org/en/latest/natspec-format.html) `@custom:strata` annotations in doc comments. No special imports or stub functions are needed.

## Annotations

| Annotation | Placement | Description |
|---|---|---|
| `@custom:strata requires <expr>` | function | Precondition — must hold on entry |
| `@custom:strata ensures <expr>` | function | Postcondition — must hold on exit |
| `@custom:strata invariant <expr>` | contract | Contract invariant — checked after constructor and on entry/exit of public functions |
| `@custom:strata modifies <vars>` | function | Frame condition — only listed state variables may change |
| `@custom:strata loop-invariant <expr>` | function | Loop invariant — maintained across loop iterations |
| `@custom:strata forall v : T :: <expr>` | in specs | Universal quantifier — property holds for all values of type T |
| `@custom:strata exists v : T :: <expr>` | in specs | Existential quantifier — property holds for some value of type T |

## Specification expressions

Specifications use Solidity expression syntax with these additions:

| Expression | Meaning |
|---|---|
| `old(expr)` | Value of `expr` before function execution |
| `forall v : T :: expr` | For all values `v` of type `T`, `expr` holds |
| `exists v : T :: expr` | There exists a value `v` of type `T` where `expr` holds |
| `a ==> b` | Implication: if `a` then `b` |
| `type(T).max` | Maximum value of integer type `T` |
| `type(T).min` | Minimum value of integer type `T` |

## Placement rules

- `requires`, `ensures`, `modifies`, `loop-invariant`: placed in the doc comment of a function.
- `invariant`: placed in the doc comment of a contract.
- `forall`, `exists`: used inside `requires`, `ensures`, `invariant`, or `loop-invariant` expressions.

## Example

```solidity
/// @custom:strata invariant totalSupply >= 0
contract Token {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    /// @custom:strata requires amount > 0
    /// @custom:strata requires balances[to] + amount <= type(uint256).max
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    /// @custom:strata modifies totalSupply, balances[to]
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balances[to] += amount;
    }
}
```
