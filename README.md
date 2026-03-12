# StrataSolidity

Solidity verification front-end for the [Strata](https://github.com/strata-org/Strata)
verification framework. Translates Solidity smart contracts through the
Strata pipeline for formal verification via SMT solving.

```
Solidity (.sol) → solc + solast.py → Ion → SolToLaurel → Laurel IR
  → LaurelToCoreTranslator → Strata Core → VCG → SMT solver (z3/cvc5)
```

## Prerequisites

- [Lean 4](https://lean-lang.org/) v4.27.0 (see `lean-toolchain`)
- [Strata](https://github.com/strata-org/Strata) checked out as a sibling directory (`../Strata`)
- Python 3.12+ (for the Solidity parser)
- [solc](https://docs.soliditylang.org/en/latest/installing-solidity.html) (Solidity compiler)
- z3 or cvc5 SMT solver

## Directory layout

```
StrataSolidity/             Lean library (dialect, parser, AST → Laurel translation)
StrataSolidityMain.lean     CLI entry point (strataSolidity executable)
StrataSolidityTest/         Integration tests (.sol files + expected output)
Tools/Solidity/             Python parser (solc JSON AST → DDM Ion serialization)
```

## Building

```bash
# Ensure Strata is checked out alongside this package
ls ../Strata/lakefile.toml  # should exist

# Build the library and CLI executable
lake build
```

## Usage

Verification is a two-stage process:

### 1. Parse Solidity to Ion

```bash
cd Tools/Solidity
python3 -m src.solast sol_to_strata \
    --dialect dialects/Solidity.dialect.st.ion \
    path/to/contract.sol \
    path/to/contract.solidity.st.ion
```

### 2. Verify via the Strata pipeline

```bash
lake exe strataSolidity path/to/contract.solidity.st.ion [--verbose]
```

The tool translates the Solidity Ion AST through Laurel IR to Strata Core,
generates verification conditions, and discharges them with z3. Output
includes per-assertion results with source locations mapped back to the
original `.sol` file.

## Writing specifications

Solidity contracts use `_strata_*` specification functions for verification:

```solidity
contract Counter {
    uint256 public count;

    /// @notice Increment the counter
    function increment() public {
        _strata_requires(count < type(uint256).max);
        _strata_ensures(_strata_old(count) + 1 == count);

        count += 1;
    }

    function _strata_invariant() internal view {
        _strata_assert(count >= 0);
    }
}
```

Available specification constructs:
- `_strata_assert(expr)` — verification assertion
- `_strata_requires(expr)` — function precondition
- `_strata_ensures(expr)` — function postcondition
- `_strata_old(expr)` — pre-state value in postconditions
- `_strata_invariant()` — contract invariant (checked on entry/exit of public functions)
- `_strata_loop_invariant(expr)` — loop invariant

## Running tests

```bash
cd StrataSolidityTest/Solidity
bash run_sol_analyze_laurel.sh
```

This runs each `tests/test_*.sol` file through the full pipeline and diffs
output against `expected/*.expected`. Tests in `known_failures.txt` are
treated as expected failures (XFAIL).

## License

Copyright Strata Contributors. SPDX-License-Identifier: Apache-2.0 OR MIT
