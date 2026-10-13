# Running StrataSolidity

Let's verify a simple token contract. Create a file called `token.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Token {
    mapping(address => uint256) public balances;

    /// @custom:strata invariant totalSupply == sum(balances)
    uint256 public totalSupply;

    /// @custom:strata modifies balances[to], totalSupply
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balances[to] += amount;
    }

    /// @custom:strata requires to != msg.sender
    /// @custom:strata requires balances[msg.sender] >= amount
    /// @custom:strata modifies balances[msg.sender], balances[to]
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    function transfer(address to, uint256 amount) external {
        require(to != msg.sender, "self-transfer disallowed");
        require(balances[msg.sender] >= amount, "insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }
}
```

Run StrataSolidity:

```bash
Tools/Solidity/scripts/strata-verify.sh token.sol
```

You should see:

```
==== Verification Results ====
✅ Passed (11):
  invariant totalSupply == sum(balances) at line 4, col 1
  ensures balances[to] == old(balances[to]) + amount at line 11, col 9
  ensures totalSupply == old(totalSupply) + amount at line 12, col 9
  modifies frame (balances) at line 13, col 5
  invariant totalSupply == sum(balances) at line 13, col 5
  heap frame (only this contract is modified) at line 13, col 5
  ensures balances[msg.sender] == old(balances[msg.sender]) - amount at line 21, col 9
  ensures balances[to] == old(balances[to]) + amount at line 22, col 9
  modifies frame (balances) at line 23, col 5
  modifies frame (totalSupply) at line 23, col 5
  invariant totalSupply == sum(balances) at line 23, col 5

11 passed, 0 failed, 0 unknown out of 11 total
```

Every obligation generated from the specification — the invariant, the postconditions, and the `modifies` frames — has been mathematically proven for all inputs and states.

## Why `to != msg.sender` matters

Remove the `requires to != msg.sender` precondition from `transfer` (and the matching `require`) and re-run. The two postconditions now contradict each other when `to == msg.sender` — the same balance can't both drop by `amount` and rise by `amount` — so some of them come back ❓ unknown instead of ✅ pass. The precondition isn't busywork: it states the case the postconditions are written for.

## Introducing a bug

Restore the precondition, then remove `totalSupply += amount;` from `mint` so the supply invariant is no longer maintained:

```solidity
function mint(address to, uint256 amount) external {
    balances[to] += amount;   // bug: totalSupply is never updated
}
```

Re-run:

```bash
Tools/Solidity/scripts/strata-verify.sh token.sol
```

```
==== Verification Results ====
❓ Unknown (2):
  invariant totalSupply == sum(balances) at line 13, col 5
  ensures totalSupply == old(totalSupply) + amount at line 12, col 9

✅ Passed (8):
  ...

8 passed, 0 failed, 2 unknown out of 10 total
```

The invariant `totalSupply == sum(balances)` and the postcondition about `totalSupply` can no longer be proven: `mint` increases `balances[to]` without increasing `totalSupply`, so the data-structure property it is supposed to maintain no longer holds. Results are ✅ pass when proven, ❌ fail when the solver finds a violation (with a counterexample when z3 produces a model), and ❓ unknown when it can neither prove nor refute the obligation. Treat ❓ as "not verified." See [Output Formats](./output_formats.md).

## Verification tools

### strata-verify.sh

The shell wrapper checks the Strata submodule, then runs the `strataSolidity` binary on one file (parse → translate → verify) in one command:

```bash
Tools/Solidity/scripts/strata-verify.sh <file.sol> [flags]
```

Run `lake build` first. You can also call the binary directly: `.lake/build/bin/strataSolidity <file.sol> [flags]`.

| Flag | Effect |
|---|---|
| `--sarif` / `--json` / `--pipeline-json` | Output format (default: plain text) |
| `--verbose` | Also print the generated Laurel and Core programs |
| `--timeout=<s>` | Per-obligation solver timeout (default 10) |
| `--strict` | Exit non-zero when any annotation or function couldn't be verified |
| `--no-array-theory` | Encode mappings with quantified select/update axioms instead of SMT arrays (the default since the 2026-10 Strata re-pin; `--array-theory` is accepted and has no effect) |
| `--dump-vc=<dir>` | Keep the generated `.smt2` files in `<dir>/<procedure>/` |
| `--assume-no-reentrancy` | Trust that external calls do not call back into the contract (see [Contract Invariants](./contract_invariants.md#external-calls-and-reentrancy)) |

In plain-text mode, the command exits with status 1 when any obligation fails or a verification error occurs.
