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

## Building

```bash
lake build
```

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

**Core:** contracts, functions (public/external/internal/private), state variables, constructors, inheritance (single and diamond), modifiers

**Types:** `uint`/`int` (all sizes 8–256), `bool`, `address`, `bytes32`, mappings, arrays (fixed and dynamic), structs, enums, user-defined value types

**Statements:** `if`/`else`, `while`, `for`, `return`, `require`, `assert`, `revert`, `unchecked` blocks, `delete`

**Expressions:** arithmetic (`+`, `-`, `*`, `/`, `%`, `**`), comparison, boolean logic, bitwise (`&`, `|`, `^`, `~`, `<<`, `>>`), ternary (`? :`), index access, member access, type casts

**Additional:**
- Modifiers (with arguments and `_` placeholder inlining)
- Events (`emit`) — treated as no-ops for verification
- `receive`/`fallback` functions
- `immutable` and `constant` variables
- Hash functions (`keccak256`, `sha256`) and `abi.encode*` — modeled as uninterpreted functions
- Inline assembly — havoc strategy (all touched state treated as unknown)
- Custom errors with `revert`
- `msg.sender`, `msg.value`, `block.*`, `tx.*` globals

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
