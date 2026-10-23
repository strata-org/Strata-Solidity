# Loop Invariants

Loops are the main challenge for automated verification. Without help, the verifier would need to reason about every possible number of iterations — which may be unbounded. A loop invariant tells the verifier what property the loop maintains, enabling it to prove correctness without unrolling.

## How loop invariants work

A loop invariant is a condition that must be true:
1. When the loop is first entered (base case).
2. After each iteration, assuming it held before (inductive step).
3. Combined with the loop exit condition, it implies the postcondition.

## Declaring a loop invariant

Loop invariants are placed on the function containing the loop:

```solidity
contract Fees {
    uint256 constant FEE_PER_ITEM = 5;

    /// @custom:strata loop-invariant i <= items
    /// @custom:strata loop-invariant fee == i * FEE_PER_ITEM
    /// @custom:strata ensures fee == items * FEE_PER_ITEM
    function totalFee(uint256 items) external pure returns (uint256 fee) {
        for (uint256 i = 0; i < items; i++) {
            fee += FEE_PER_ITEM;
        }
    }
}
```

(A constant declared outside the contract is not supported.)

StrataSolidity checks that:
- `i <= items` and `fee == i * FEE_PER_ITEM` hold before the loop starts
  (`i` and `fee` are both 0).
- If they hold at the start of an iteration, they still hold at the end: the
  body adds `FEE_PER_ITEM` to `fee` and 1 to `i`.
- When the loop exits (`i == items`), the invariants imply the postcondition.

The invariant `fee == i * FEE_PER_ITEM` connects the loop body to the
postcondition: it states how far the accumulator has progressed. Without it,
`fee == items * FEE_PER_ITEM` cannot be proven, and a body that added the
wrong amount would break it.

## `old()` and state in a loop

In a loop invariant, `old(e)` is the value of `e` at the function's entry,
as in `ensures` (not at the loop's entry):

```solidity
/// @custom:strata requires n <= 100
/// @custom:strata loop-invariant t == old(total) + i
/// @custom:strata loop-invariant i <= n
/// @custom:strata ensures total == old(total) + n
function addN(uint256 n) external {
    uint256 t = total;
    for (uint256 i = 0; i < n; i++) {
        t += 1;
    }
    total = t;
}
```

Here the loop updates a local and the state is written after it. A loop
that writes a state variable itself is verified as well, but the
function's `heap frame (only this contract is modified)` obligation is then
reported unknown (❓): see [Current Limitations](./limitations.md).

## Why loop invariants matter for smart contracts

Most smart contract bugs involving loops are:
- **Off-by-one errors** in iteration bounds
- **Accumulator errors** where a running total drifts from the expected value
- **Unbounded gas** from loops over dynamic arrays

Loop invariants catch these mathematically. A well-chosen invariant connects the loop body to the postcondition through induction — the same technique used in mathematical proofs.

## When are loop invariants needed?

If your function has no loops, you don't need loop invariants. StrataSolidity can verify straight-line code and branching (`if`/`else`) automatically.

If your function has a loop and a postcondition that depends on the loop's result, you almost certainly need a loop invariant. Without one, the SMT solver has no way to connect the loop body to the postcondition.
