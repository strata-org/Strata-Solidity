# Installation

StrataSolidity can currently only be used by building from source.

## Prerequisites

1. **[Lean 4](https://lean-lang.org/)** (via `elan`; the version is pinned in `lean-toolchain`) — needed to build StrataSolidity and the [Strata](https://github.com/strata-org/Strata) back-end.
2. **[Strata](https://github.com/strata-org/Strata)** vendored as a git submodule at `./Strata`.
3. **Python 3.12+** — only for development and CI tooling (the SARIF schema check and the benchmark CSV check). You don't need it to verify contracts.
4. **[solc](https://docs.soliditylang.org/en/latest/installing-solidity.html)** — the Solidity compiler (used for AST extraction only).
5. **[z3](https://github.com/Z3Prover/z3/releases)** SMT solver on your `PATH`. CI uses z3 4.15.4 (pinned in `.github/workflows/ci.yml`). Another version can decide some obligations differently, typically reporting `unknown` where 4.15.4 proves or refutes, so use 4.15.4 to reproduce CI's results and the golden files under `test/expected/`.

## Building

1. Check out the StrataSolidity repository with submodules:
   ```bash
   git clone --recurse-submodules https://github.com/strata-org/Strata-Solidity.git
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

This compiles the Lean translation pipeline and the `strataSolidity` CLI executable at `.lake/build/bin/strataSolidity`.

## Verifying the installation

Run the included test suites:

```bash
lake test               # Lean unit and characterization tests
bash test/run_tests.sh  # golden suite (test/examples/*.sol vs test/expected/) and exit-code checks
```

The golden suite runs each example contract through the full pipeline and diffs the result against the expected output. If both pass, your installation is working correctly.
