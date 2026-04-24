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
/// @custom:strata loop-invariant i <= users.length
/// @custom:strata loop-invariant sum >= 0
/// @custom:strata ensures sum >= 0
function sumBalances(address[] calldata users) external view returns (uint256 sum) {
    for (uint i = 0; i < users.length; i++) {
        sum += balances[users[i]];
    }
}
```

StrataSolidity checks that:
- `i <= users.length` and `sum >= 0` hold before the loop starts.
- If they hold at the start of an iteration, they still hold at the end.
- When the loop exits (`i == users.length`), the invariants plus the exit condition are sufficient to prove the postcondition.

## Why loop invariants matter for smart contracts

Most smart contract bugs involving loops are:
- **Off-by-one errors** in iteration bounds
- **Accumulator errors** where a running total drifts from the expected value
- **Unbounded gas** from loops over dynamic arrays

Loop invariants catch these mathematically. A well-chosen invariant connects the loop body to the postcondition through induction — the same technique used in mathematical proofs.

## When are loop invariants needed?

If your function has no loops, you don't need loop invariants. StrataSolidity can verify straight-line code and branching (`if`/`else`) automatically.

If your function has a loop and a postcondition that depends on the loop's result, you almost certainly need a loop invariant. Without one, the SMT solver has no way to connect the loop body to the postcondition.
