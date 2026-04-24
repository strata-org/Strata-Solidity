# StrataSolidity

> **Current status:** StrataSolidity is under active development and currently supports a substantial subset of Solidity. It is built on [Strata](https://github.com/strata-org/Strata). See [Supported Solidity Features](./supported_features.md) and [Current Limitations](./limitations.md) for details.

StrataSolidity is a formal verification tool for Solidity smart contracts. It mathematically proves that your contract behaves according to its specification — not by testing a few inputs, but by checking *all possible* inputs and states.

Smart contract bugs are uniquely costly. Deployed contracts are immutable, transactions are irreversible, and exploits can drain millions in seconds. Testing helps, but it can only check the cases you think of. Formal verification checks every case.

## How it works

StrataSolidity translates annotated Solidity contracts through the Strata pipeline for verification via SMT solving:

```
Solidity (.sol) → solc + solast.py → Ion → SolToLaurel → Laurel IR
  → LaurelToCoreTranslator → Strata Core → VCG → SMT solver (z3/cvc5)
```

You write specifications as `@custom:strata` annotations in standard NatSpec comments — no special imports, no stub functions, no separate specification language. Your specs live alongside your code:

```solidity
/// @custom:strata requires balances[msg.sender] >= amount
/// @custom:strata ensures balances[to] == old(balances[to]) + amount
function transfer(address to, uint256 amount) external {
    // ...
}
```

StrataSolidity then proves (or disproves) that the implementation satisfies these specifications.

## Why Solidity is a good fit for formal verification

Solidity's execution model is simpler than most general-purpose languages:

- **No heap aliasing** — storage is a flat key-value store. Two state variables cannot point to the same memory.
- **No concurrency** — the EVM is single-threaded.
- **No dynamic dispatch** — inheritance exists but external calls are explicit.
- **Deterministic execution** — same inputs always produce same outputs.

These properties eliminate entire classes of verification complexity that tools for Java, Rust, or C must handle.

## Frequently asked questions

#### Should I use StrataSolidity in production right now?
Not yet. The tool is under active development and does not yet cover all Solidity patterns. However, you can use the [Installation](./installation.md) and [Running StrataSolidity](./first_verification.md) sections to explore what it can currently do.

#### How do I write specifications?
Specifications are written as [NatSpec](https://docs.soliditylang.org/en/latest/natspec-format.html) `@custom:strata` annotations in doc comments. See the [Annotation Reference](./annotation_reference.md) for the full list.

#### Why NatSpec comments instead of a library?
Solidity's compiler (solc) is licensed under GPL-3.0. Building a compiler plugin would create a derivative work with GPL obligations. NatSpec comments avoid any compiler modification — we use solc only to produce the AST. NatSpec is also the standard mechanism for structured metadata in Solidity, already used by Etherscan, documentation generators, and static analysis tools.

#### Can StrataSolidity prove that code has a bug?
Currently, StrataSolidity can prove the *absence* of bugs but cannot generate concrete counterexamples. If verification fails, you know something is wrong, but you won't yet get values like "fails when `amount = 5, balance = 3`."

#### Which SMT solvers are supported?
z3 and cvc5. Either one works — z3 is the default.

# This guide

This guide assumes you're already familiar with Solidity. Specifications used by StrataSolidity are written as NatSpec annotations using Solidity expressions. However, verifying contract correctness introduces concepts beyond regular Solidity — preconditions, postconditions, invariants, and quantifiers. This guide walks you through each concept with concrete examples.
