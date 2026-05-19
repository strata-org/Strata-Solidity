# StrataSolidity

Solidity formal verification front-end for the [Strata](https://github.com/strata-org/Strata) framework. Translates annotated Solidity contracts through the Strata pipeline for verification via SMT solving.

```
Solidity (.sol) → solc + solast.py → Ion → SolToLaurel → Laurel IR
  → LaurelToCoreTranslator → Strata Core → VCG → SMT solver (z3/cvc5)
```

## Prerequisites

- [Lean 4](https://lean-lang.org/) v4.27.0 (see `lean-toolchain`)
- [Strata](https://github.com/strata-org/Strata) checked out as a sibling directory (`../Strata`)
- Python 3.12+
- [solc](https://docs.soliditylang.org/en/latest/installing-solidity.html) (Solidity compiler)
- z3 or cvc5 SMT solver

### Checking the `../Strata` sibling path

The Lake package wires Strata in via `[[require]] path = "../Strata"` (see `lakefile.toml`). If the sibling checkout is missing or at the wrong location, `lake build` and every wrapper script fails deep in the toolchain with an opaque error.

Run `scripts/check-strata-sibling.sh` from the repo root to verify the sibling is in place before building:

```bash
scripts/check-strata-sibling.sh
```

The helper exits non-zero with a friendly message when `../Strata/lakefile.toml` is missing. It is invoked automatically at the top of `Tools/Solidity/scripts/strata-verify.sh`, `bench/bench.sh`, and `test/run_tests.sh`, so the same precondition is enforced for the verification pipeline, the benchmark harness, and the test runner.

## Building

```bash
lake build
```

## Continuous integration

`.github/workflows/ci.yml` runs on push to `main`, `feat/**`, `fix/**`, and on every pull request. The workflow:

1. Checks out StrataSolidity into `./StrataSolidity` and the sibling `strata-org/Strata` into `./Strata` (pinned by SHA; override via the `strata_ref` workflow_dispatch input)
2. Verifies the sibling layout via `scripts/check-strata-sibling.sh`
3. Installs `solc` (via the `ethereum/ethereum` PPA) and the Python dev dependencies in `Tools/Solidity/requirements-dev.txt`
4. Runs `lake build` and `lake test` via [`leanprover/lean-action`](https://github.com/leanprover/lean-action) (which handles elan install and `.lake` caching)
5. Runs `test/run_tests.sh` (golden suite + REQ-PBT-007 exit-code sub-stage)
6. Runs `python3 bench/check_csv_schema.py bench/results.csv` (REQ-PBT-008 schema enforcer against the committed CSV)
7. Runs `python3 -m pytest Tools/Solidity/test` (REQ-PBT-004 SARIF 2.1.0 schema compliance)

`bench/bench.sh` itself is intentionally not in the hot path (b6_erc20 is slow). The primary golden harness `StrataSolidityTest/Solidity/run_sol_analyze_laurel.sh` is also not wired (see `StrataSolidityTest/Solidity/CHECKPOINT_GAP.md`).

## Quick start

```bash
# One-step verification
Tools/Solidity/scripts/strata-verify.sh contract.sol

# With SARIF output
Tools/Solidity/scripts/strata-verify.sh contract.sol --sarif
```

## Specification language

Specifications are written as [NatSpec](https://docs.soliditylang.org/en/latest/natspec-format.html) `@custom:strata` annotations in doc comments. No stub functions or special imports needed.

### Annotations

| Annotation | Placement | Description |
|---|---|---|
| `@custom:strata requires <expr>` | function | Precondition — must hold on entry |
| `@custom:strata ensures <expr>` | function | Postcondition — must hold on exit; supports `old(expr)` for pre-state values |
| `@custom:strata invariant <expr>` | contract | Contract invariant — checked after constructor and on entry/exit of public functions |
| `@custom:strata modifies <vars>` | function | Frame condition — only listed state variables may change |
| `@custom:strata loop-invariant <expr>` | function | Loop invariant — maintained across loop iterations |
| `@custom:strata forall v : T :: <expr>` | function | Universal quantifier |
| `@custom:strata exists v : T :: <expr>` | function | Existential quantifier |

### Example: ERC20-like token

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:strata invariant totalSupply >= 0
contract Token {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    /// @custom:strata requires balances[to] <= 100000
    /// @custom:strata ensures totalSupply == old(totalSupply) + amount
    function mint(address to, uint256 amount) external {
        require(amount <= 10000, "amount too large");
        require(totalSupply <= 100000, "supply too large");
        totalSupply += amount;
        balances[to] += amount;
    }

    /// @custom:strata requires balances[msg.sender] >= amount
    /// @custom:strata requires to != msg.sender
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    function transfer(address to, uint256 amount) external {
        require(to != msg.sender, "self-transfer disallowed");
        require(balances[msg.sender] >= amount, "insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }

    /// @custom:strata modifies x
    /// @custom:strata ensures forall a : address :: balances[a] >= 0
    function checkInvariant() external view {}
}
```

## Supported Solidity features

StrataSolidity accepts a subset of Solidity 0.8.x covering contracts and interfaces, functions and modifiers, common value and reference types (integers, `bool`, `address`, `bytes32`, mappings, arrays, structs, enums), standard control flow and expressions, and NatSpec-annotated specifications. Pipeline-specific conventions (events as no-ops, hashes and ABI encoders as uninterpreted functions, inline assembly under a havoc strategy) are part of the accepted subset.

For the authoritative, per-feature enumeration, see [`.kiro/specs/strata-solidity-baseline/requirements.md`](.kiro/specs/strata-solidity-baseline/requirements.md) §3 — Supported Solidity Subset (REQ-SOL-001..REQ-SOL-100). That document is the source of truth; this README intentionally does not duplicate the list to avoid drift.

## Output formats

**Plain text** (default): per-assertion results with source locations.

```
==== Contract: Token ====
  mint:
    [line 8] postcondition: ✅ pass
  transfer:
    [line 14] precondition: ✅ pass
    [line 16] postcondition: ❌ fail
```

**SARIF 2.1.0** (`--sarif`): machine-readable JSON for CI integration, conforming to the [SARIF](https://sarifweb.azurewebsites.net/) standard.

## Verification tools

### strata-verify.sh

Shell wrapper that runs the full pipeline (parse → translate → verify) in one command.

```bash
Tools/Solidity/scripts/strata-verify.sh <file.sol> [--sarif] [--verbose]
```

Requires `lake build` to have been run first.

### strata_verify.py

Python wrapper with two modes:

**File mode:**
```bash
python3 -m src.strata_verify --file contract.sol [--sarif]
```

**Standard-JSON mode** (solc-compatible):
```bash
echo '{"language":"Solidity","sources":{"file.sol":{"content":"..."}},"settings":{"modelChecker":{"engine":"strata"}}}' \
  | python3 -m src.strata_verify
```

Returns solc-compatible JSON with verification results in the `errors` array.

## Directory layout

```
StrataSolidity/             Lean library (dialect, parser, AST → Laurel translation)
StrataSolidityMain.lean     CLI entry point (strataSolidity executable)
StrataSolidityTest/         Integration tests (.sol files + expected output)
Tools/Solidity/             Python parser and verification wrappers
  src/solast.py             solc JSON AST → Ion serialization
  src/strata_verify.py      Python verification wrapper
  scripts/strata-verify.sh  Shell verification wrapper
```

## Running tests

```bash
cd StrataSolidityTest/Solidity
bash run_sol_analyze_laurel.sh
```

Runs each `tests/test_*.sol` through the full pipeline and diffs against `expected/*.expected`. Tests in `known_failures.txt` are treated as expected failures (XFAIL).

## License

Copyright Strata Contributors. SPDX-License-Identifier: Apache-2.0 OR MIT
