# Installation

StrataSolidity can currently only be used by building from source.

## Prerequisites

1. **[Lean 4](https://lean-lang.org/)** v4.27.0 (via `elan`) — needed to build StrataSolidity and the [Strata](https://github.com/evertonfraga/Strata/tree/solidity) back-end.
2. **[Strata](https://github.com/evertonfraga/Strata/tree/solidity)** vendored as a git submodule at `./Strata`.
3. **Python 3.12+** — used by the parser (`solast.py`).
4. **[solc](https://docs.soliditylang.org/en/latest/installing-solidity.html)** — the Solidity compiler (used for AST extraction only).
5. **z3** or **cvc5** SMT solver on your `PATH`.

## Building

1. Check out the StrataSolidity repository with submodules:
   ```bash
   git clone --recurse-submodules https://github.com/evertonfraga/StrataSolidity.git
   # or, after a plain clone:
   git submodule update --init --recursive
   ```
2. Verify the submodule layout:
   ```bash
   bash scripts/check-strata.sh
   ```
3. Build:
   ```bash
   lake build
   ```

This compiles the Lean translation pipeline and the `strataSolidity` CLI executable.

## Verifying the installation

Run the included test suite:

```bash
cd StrataSolidityTest/Solidity
bash run_sol_analyze_laurel.sh
```

This runs each test contract through the full pipeline and diffs against expected output. If all tests pass, your installation is working correctly.
