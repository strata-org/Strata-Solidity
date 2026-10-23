# StrataSolidity

Solidity formal verification front-end for the [Strata](https://github.com/strata-org/Strata) framework. Translates annotated Solidity contracts through the Strata pipeline for verification via SMT solving.

```
Solidity (.sol) → solc --standard-json → SolcAstParser (Lean) → SolTranslator
  → Laurel IR → Laurel compilation pipeline → Strata Core → VCG → SMT solver (z3)
```

The entire pipeline lives in the `strataSolidity` binary: it invokes `solc`,
parses the JSON AST into typed Lean structures, and verifies — no Python,
no intermediate serialization.

## Prerequisites

- [Lean 4](https://lean-lang.org/) (see `lean-toolchain` for the pinned version)
- [Strata](https://github.com/strata-org/Strata) — vendored as a git submodule at `./Strata` (see [Strata submodule](#strata-submodule) below)
- [solc](https://docs.soliditylang.org/en/latest/installing-solidity.html) (Solidity compiler)
- [z3](https://github.com/Z3Prover/z3/releases), the SMT solver, on your `PATH` (cvc5 is not supported)
- Python 3.12+ — dev/CI tooling only (SARIF schema check, bench CSV enforcer); not needed to verify contracts

### Strata submodule

StrataSolidity vendors the [Strata framework](https://github.com/strata-org/Strata) as a git submodule at `./Strata`, wired through `lakefile.lean`'s `require Strata from "Strata"` (see `lake-manifest.json`, which also pins Strata's own dependency, [Strata-DDM](https://github.com/strata-org/Strata-DDM)). The submodule is pinned to an explicit upstream `main` commit; see [`docs/upstream-strata-migration-plan.md`](docs/upstream-strata-migration-plan.md) for the current pin and what changed upstream. Clone with submodules so the dependency is materialized before `lake build`:

```bash
git clone --recurse-submodules https://github.com/strata-org/Strata-Solidity.git
# or, after a plain clone:
git submodule update --init --recursive
```

`scripts/check-strata.sh` exits non-zero with a friendly message when `Strata/lakefile.toml` is missing. It is invoked automatically at the top of `Tools/Solidity/scripts/strata-verify.sh`, `bench/bench.sh`, and `test/run_tests.sh`, so the same precondition is enforced for the verification pipeline, the benchmark harness, and the test runner.

## Building

```bash
lake build
```

## Continuous integration

`.github/workflows/ci.yml` runs on push to `main`, `feat/**`, `fix/**`, and on every pull request. The workflow:

1. Checks out StrataSolidity with `submodules: recursive` so the Strata submodule is materialized at the recorded SHA
2. Verifies the submodule layout via `scripts/check-strata.sh`
3. Installs `solc` (via the `ethereum/ethereum` PPA) and the CI-only Python deps in `Tools/Solidity/requirements-dev.txt`
4. Runs `lake build` and `lake test` via [`leanprover/lean-action`](https://github.com/leanprover/lean-action), which handles elan install and caches the root `.lake`; Strata builds into `Strata/.lake`, which separate steps restore and save, keyed on the toolchain, the manifest and the submodule commit
5. Runs `test/run_tests.sh` (golden suite + REQ-PBT-007 exit-code sub-stage)
6. Runs `python3 bench/check_csv_schema.py bench/results.csv` (REQ-PBT-008 schema enforcer against the committed CSV)
7. Runs `python3 -m pytest Tools/Solidity/test` (REQ-PBT-004 SARIF 2.1.0 schema compliance)
8. Builds the documentation site, and checks the capability ledger (`python3 scripts/capabilities.py --check`, see [Supported features](#supported-solidity-features))

`bench/bench.sh` itself is intentionally not in the hot path (b6_erc20 is slow).

Lean panics are errors in CI. A `panic!` prints a message and continues with
a default value, which in the verifier could mean a wrong verdict, so every
step that compiles or runs StrataSolidity sets `LEAN_ABORT_ON_PANIC=1`. One
upstream module, `Strata.DL.Lambda.LExprEvalProps`, is built first without
it: Lean 4.31 panics while writing that module (a known upstream issue that
does not affect the checked proofs), and CI reports it as a warning. Set
`LEAN_ABORT_ON_PANIC=1` locally to get the same behavior.

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

<!-- capabilities:begin annotations -->
<!-- Generated from docs/capabilities.toml by scripts/capabilities.py: edit the ledger, then run the script. -->
| Annotation | Placement | Meaning |
|---|---|---|
| `@custom:strata requires <expr>` | Function | Precondition: assumed on entry, checked at each internal call |
| `@custom:strata ensures <expr>` | Function | Postcondition: checked on exit; `old(e)` is the value of `e` on entry |
| `@custom:strata invariant <expr>` | Contract or state variable | Checked after the constructor and on exit of every public or external function that may change state, assumed on their entry and by `view` functions |
| `@custom:strata modifies <vars>` | Function | Frame: only the listed state variables, or mapping keys, may change |
| `@custom:strata loop-invariant <expr>` | Function | Holds on entry to the function's loop and is preserved by its body |
<!-- capabilities:end annotations -->

Inside these, `old(e)`, `sum(m)`, `forall v : T :: P` and `exists v : T :: P`
are expressions, and a `//` starts a comment. The
[annotation reference](docs/guide/src/annotation_reference.md) has the full
syntax.

### Example: ERC20-like token

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

Every annotation here pulls its weight:

- The **invariant** `totalSupply == sum(balances)` is the central data-structure
  property of a token — it is checked on every mutating function, and deleting
  `totalSupply += amount` from `mint` means it can no longer be proven (❓
  unknown: the update axiom of `sum` is quantified, so z3 does not refute it).
- **`modifies` is key-scoped**: `modifies balances[to], totalSupply` generates a
  frame condition that *every other holder's balance is unchanged* — the
  property that traditional spec-file tools must assert by hand.
- The **`ensures`** clauses state the exact effect in terms of pre-state.

### Keep specs crisp

Don't state what the type system or the tool already guarantees:

- `uint256` values are non-negative — never write `requires amount >= 0` or
  `invariant totalSupply >= 0`; the verifier assumes non-negativity for every
  unsigned integer automatically.
- State not listed in `modifies` is unchanged — never write
  `ensures x == old(x)` for a variable the function doesn't modify; the frame
  condition already asserts it.
- Prefer `modifies m[k]` over `modifies m` whenever the touched keys are
  expressible: the narrower frame is both a stronger theorem and free
  documentation of the function's write-set.

## Supported Solidity features

StrataSolidity verifies a subset of Solidity 0.8.x. In short:

<!-- capabilities:begin highlights -->
<!-- Generated from docs/capabilities.toml by scripts/capabilities.py: edit the ledger, then run the script. -->
**Works today:**

- Simple and nested mappings, with `old()`
- Contract invariants, including `sum(mapping)`, checked across external calls that may re-enter the contract
- Key-scoped `modifies` frame conditions
- `forall` quantifiers, with `==>`
- Loop invariants, with `old()`
- Inheritance: inherited state, functions, modifiers, invariants and constructors, and `super`
- Integer conversions, wrapping and signed division as the EVM performs them
- Plain-text, JSON and SARIF output, with counterexamples when z3 produces a model

**Not yet:**

- Struct-valued mappings and arrays of structs (functions using them are not verified)
- Library calls and `using … for`
- `revert("reason")` (`require` and custom errors work)
- Strings and dynamic `bytes` values
- Array `pop()`
- Constructors that call internal functions using state (the `_mint` pattern)
- A base contract imported from another file
- Conclusive results for every property over `sum`, `forall` and key-scoped frames: some are ❓ unknown
<!-- capabilities:end highlights -->

[`LIMITATIONS.md`](LIMITATIONS.md) lists every feature with its status,
generated from the capability ledger
[`docs/capabilities.toml`](docs/capabilities.toml), in which each entry
names the test fixtures that show it. `python3 scripts/capabilities.py
--check` (run by CI) fails when a fixture no longer shows what its entry
says, or a generated table is out of date.

## Output formats

**Plain text** (default): the obligations, grouped by result, with source
locations, then the totals. For the example above:

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

A refuted obligation (❌) is listed under `❌ Failures` with a counterexample,
and one the solver could not decide (❓) under `❓ Unknown`. See
[Output Formats](docs/guide/src/output_formats.md).

**JSON** (`--json`): a flat array of results, for scripts.

**SARIF 2.1.0** (`--sarif`): machine-readable JSON for CI integration, conforming to the [SARIF](https://sarifweb.azurewebsites.net/) standard.

## Verification tools

### strata-verify.sh

Shell wrapper that runs the full pipeline (parse → translate → verify) in one command.

```bash
Tools/Solidity/scripts/strata-verify.sh <file.sol> [options]
```

Requires `lake build` to have been run first. The options:

<!-- capabilities:begin flags -->
<!-- Generated from docs/capabilities.toml by scripts/capabilities.py: edit the ledger, then run the script. -->
| Option | Effect |
|---|---|
| `--json` | A flat JSON array of results (see [Output Formats](docs/guide/src/output_formats.md)) |
| `--sarif` | SARIF 2.1.0, for code scanning (see [SARIF](docs/guide/src/sarif.md)); takes precedence over `--json` |
| `--pipeline-json` | One JSON object with the generated Laurel and Core programs, the obligations and their SMT files, and the warnings |
| `--strict` | Exit 1 when an obligation is refuted or unknown, or an annotation or function was not verified, in every output format |
| `--verbose` | Also print the generated Laurel and Core programs, to standard output (so the output of `--json` and `--sarif` is no longer valid JSON) |
| `--timeout=<s>` | Solver time limit per obligation, in seconds (default 10; `0` means none) |
| `--assume-no-reentrancy` | Trust that external calls do not call back into the contract, so they leave its state unchanged (see [Contract Invariants](docs/guide/src/contract_invariants.md#external-calls-and-reentrancy)) |
| `--no-array-theory` | Encode mappings with quantified select/update axioms instead of SMT arrays (the default); more results are then unknown |
| `--array-theory` | Accepted for compatibility; has no effect |
| `--dump-vc=<dir>` | Keep the generated `.smt2` files, in `<dir>/<procedure>/` |
| `--from-sol` | Read the input as Solidity whatever its name (a `.sol` file is read as Solidity anyway) |
| `--sol-source=<file>` | Take source positions and annotation text from `<file>`, for an input that is not the source file itself (the legacy `.solidity.st.ion` input) |
| `STRATA_SMT_DIR=<dir>` | Environment variable: write the SMT files to `<dir>` (`--pipeline-json` uses `/tmp/strata-pipeline-smt`). Each run first deletes every `.smt2` file and every subdirectory in it: give it a directory of its own. |
<!-- capabilities:end flags -->

## Directory layout

```
StrataSolidity/             Lean library (dialect, parser, AST → Laurel translation)
StrataSolidityMain.lean     CLI entry point (strataSolidity executable)
StrataSolidityTest/         Lean unit and characterization tests (lake test)
test/                       Golden suite: examples/*.sol and their expected/ results
docs/capabilities.toml      Capability ledger (what is verified, with its tests)
docs/guide/                 User guide (mdBook sources, also built into docs/site/)
scripts/capabilities.py     Checks the ledger, generates the feature tables
Tools/Solidity/
  scripts/strata-verify.sh  Thin shell wrapper around the binary
  test/                     SARIF schema and counterexample checks (CI-only Python)
```

## Running tests

```bash
lake test               # Lean unit + characterization tests (#guard suites, JSON/pipeline-JSON shape)
bash test/run_tests.sh  # golden suite (test/examples/*.sol vs test/expected/) + exit-code contract
python3 scripts/capabilities.py --check   # the capability ledger against the golden files
```

The golden suite pins the verdict of every obligation, so a change that
flips one property from proven to refuted (or back) fails even when the
totals stay the same. A comment line starting with `// Passes`,
`// Fails`, `// Refuted` or `// Not proven` in a fixture states the
intended outcome of the obligations below it, and is checked too. After a
deliberate change in results, rewrite the golden files with
`UPDATE=1 bash test/run_tests.sh` and review the diff. In CI a fixture
without a golden file fails. The header of `test/run_tests.sh` has the
details.

## License

Copyright Strata Contributors. SPDX-License-Identifier: Apache-2.0 OR MIT
