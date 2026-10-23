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

<!-- capabilities:begin flags -->
<!-- Generated from docs/capabilities.toml by scripts/capabilities.py: edit the ledger, then run the script. -->
| Option | Effect |
|---|---|
| `--json` | A flat JSON array of results (see [Output Formats](./output_formats.md)) |
| `--sarif` | SARIF 2.1.0, for code scanning (see [SARIF](./sarif.md)); takes precedence over `--json` |
| `--pipeline-json` | One JSON object with the generated Laurel and Core programs, the obligations and their SMT files, and the warnings |
| `--strict` | Exit 1 when an obligation is refuted or unknown, or an annotation or function was not verified, in every output format |
| `--verbose` | Also print the generated Laurel and Core programs, to standard output (so the output of `--json` and `--sarif` is no longer valid JSON) |
| `--timeout=<s>` | Solver time limit per obligation, in seconds (default 10; `0` means none) |
| `--assume-no-reentrancy` | Trust that external calls do not call back into the contract, so they leave its state unchanged (see [Contract Invariants](./contract_invariants.md#external-calls-and-reentrancy)) |
| `--no-array-theory` | Encode mappings with quantified select/update axioms instead of SMT arrays (the default); more results are then unknown |
| `--array-theory` | Accepted for compatibility; has no effect |
| `--dump-vc=<dir>` | Keep the generated `.smt2` files, in `<dir>/<procedure>/` |
| `--from-sol` | Read the input as Solidity whatever its name (a `.sol` file is read as Solidity anyway) |
| `--sol-source=<file>` | Take source positions and annotation text from `<file>`, for an input that is not the source file itself (the legacy `.solidity.st.ion` input) |
| `STRATA_SMT_DIR=<dir>` | Environment variable: write the SMT files to `<dir>` (`--pipeline-json` uses `/tmp/strata-pipeline-smt`). Each run first deletes every `.smt2` file and every subdirectory in it: give it a directory of its own. |
<!-- capabilities:end flags -->

In plain-text mode, the command exits with status 1 when any obligation fails or a verification error occurs; see [Output Formats](./output_formats.md) for the other formats and `--strict`.
