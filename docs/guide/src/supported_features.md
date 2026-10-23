# Supported Solidity Features

StrataSolidity verifies a subset of Solidity 0.8. This page lists what it
verifies, by area, including what it verifies only in part; [Current
Limitations](./limitations.md) lists what it does not verify. Both pages
are generated from the capability ledger (`docs/capabilities.toml` in the
repository), whose entries name the tests that show them.

<!-- capabilities:begin supported -->
<!-- Generated from docs/capabilities.toml by scripts/capabilities.py: edit the ledger, then run the script. -->
## Specifications

| Feature | Status | Notes |
|---|---|---|
| `requires`, `ensures` | ✅ Verified | A precondition is assumed on entry and checked at each internal call; a postcondition is checked on every path that returns. |
| `old(e)` | ✅ Verified | The value of `e` when the function was entered: of a scalar, a mapping, a mapping entry or an array length. |
| Contract invariants (`invariant`) | ✅ Verified | Written above the contract or on a state variable. Checked after the constructor (explicit or implicit) and at the exit of every public or external function that may change state, and assumed at their entry; assumed by `view` functions; not assumed by internal functions. `old()` is rejected in an invariant. |
| `sum(m)` of a mapping | ✅ Verified | The sum of all values of `m`, updated at every write. Its update axiom is quantified, so an obligation that involves it may be unknown (❓) instead of refuted. |
| `modifies` frames: variables and mapping keys | ✅ Verified | `modifies x, m[k]`: every other state variable, and every other key of `m`, is unchanged. A key may use parameters, constants and hashes (`roles[DEFAULT_ADMIN_ROLE]`). A function without `modifies` may change any state. Frames are not checked for constructors (a warning says so). |
| Loop invariants (`loop-invariant`) | ✅ Verified | Checked on entry to the loop and preserved by its body, for `for`, `while` and `do`-`while` loops, with `break` and `continue`. |
| `old(e)` in a loop invariant | ✅ Verified | The value of `e` at the function's entry, as in `ensures`, not at the loop's entry. |
| A loop that writes contract state | ⚠️ Partly | The function's `heap frame (only this contract is modified)` obligation is unknown (❓): the loop does not keep the fact that only this contract's state changes. Its invariants and postconditions are checked as usual. Writing a local in the loop, and the state after it, avoids this. |
| `forall v : T :: P` | ✅ Verified | `v` ranges over the values of `T`. An obligation with a `forall` among its assumptions may be unknown (❓): z3 does not instantiate quantifiers by model search. |
| `exists v : T :: P` | ⚠️ Partly | `v` ranges over the values of `T`. z3 does not search for witnesses, so a true `exists` is often unknown (❓); it is proven when the witness is at hand (a value the function wrote). |
| Operators in specifications | ✅ Verified | `==`, `!=`, `<`, `<=`, `>`, `>=`, `+`, `-`, `*`, `/`, `%`, `&&`, &#124;&#124;, `!`, `==>`, unary `-`, `m[k]`, `s.f`, `a.length`, `type(T).min` and `type(T).max`, named constants. Arithmetic is on unbounded integers (no wrapping); `/` and `%` round toward zero, as in Solidity. |
| `msg.sender`, `msg.value`, `block.*`, `tx.*` and `this` in specifications | ✅ Verified | The values of the transaction the function runs in (see Transaction values). |
| A `//` comment after an annotation | ✅ Verified | `ensures x == 1 // the new value`: the text from `//` on is not read. |

## Contracts and functions

| Feature | Status | Notes |
|---|---|---|
| Contracts, state variables, functions of any visibility, constructors, `receive`, `fallback` | ✅ Verified | Every function of every contract in the file is verified against its own specification; `view` and `pure` functions too. |
| Internal calls | ✅ Verified | Modular: the callee's `requires` is checked at the call, and after it the caller knows what the callee's `ensures` and `modifies` say. After a call of a function without a specification, its results and the state are unknown, so give helpers a specification. Named arguments are bound by name. |
| Modifiers | ✅ Verified | Inlined into each function that uses them, the first one outermost, with their arguments: `_` stands for the rest of the function, and a `return` in the function still runs the code after `_`. |
| Interfaces, abstract contracts, functions without a body | ✅ Verified | A function without a body may do anything a function of its kind may: a mutating one may change any state. An interface or library contributes no invariants. |
| Overloaded functions | ✅ Verified | Each overload is verified, and a call goes to the one solc selects. Overloads that differ only between integer and address parameters fail to translate. |
| Events, custom errors, `revert CustomError(…)` | ✅ Verified | `emit` changes nothing (its arguments are still evaluated); `revert` ends the path. |

## Inheritance

| Feature | Status | Notes |
|---|---|---|
| Inheritance: single, multiple, diamond | ✅ Verified | A contract is verified as the flattening of its bases and itself, ordered by solc's C3 linearization: inherited state, functions, modifiers and invariants are checked in its context (an obligation of an inherited function says so: `(in D)`), and a call of a virtual function calls the most derived override. A public state variable that overrides a function replaces it. |
| Base constructors | ✅ Verified | Run after the state-variable initializers and before the derived constructor, most base first, each with its own modifiers and the arguments a derived constructor gives it (`constructor() Base(7)`). |
| Base constructor arguments in an inheritance specifier (`is Base(7)`) | ⚠️ Unknown values | Not read (the AST the translator receives does not keep them): the base constructor runs with unknown values of its parameter types. (GAP-009) |
| `super.f(…)`, `Base.f(…)` | ✅ Verified | `super` follows the linearization of the contract being verified, from the contract the call is written in (also in a modifier or a base constructor); `Base.f()` calls the first implementation of `f` in `Base`'s linearization. Named arguments are bound by name. |

## Types and arithmetic

| Feature | Status | Notes |
|---|---|---|
| `uint8` … `uint256`, `int8` … `int256` | ✅ Verified | A value is in its type's range: parameters, state variables, results of calls and hashes. Signed state is not assumed to be non-negative. |
| Checked arithmetic (outside `unchecked`) | ⚠️ Partly | Computed on unbounded integers: an overflow is not modelled as a revert, so the verifier also considers the execution continuing with the out-of-range value. That only adds behaviors: a property that relies on the revert may not be proven (see [Integers](./integers.md)). |
| `unchecked` arithmetic | ✅ Verified | Wraps around as in the EVM: `+`, `-`, `*`, signed `/`, a power of constants, `++`, `--`, unary `-` and `op=`. |
| Type conversions | ✅ Verified | Narrowing truncates (two's complement), a `bytesN` conversion keeps the high bytes, widening keeps the value. |
| `/` and `%` | ✅ Verified | Signed `/` and `%` round toward zero. A zero divisor is an obligation (`divisor is non-zero`). |
| Constant expressions, named constants, `1e18`, `2.5 ether`, `2 days` | ✅ Verified | The value solc computes, exactly (rational intermediate values, units, exponents); a power of constants is folded. |
| Bitwise operators and shifts | ⚠️ Partly | `~` and shifts by a constant are exact; `&`, &#124;, `^` and shifts by a variable are unknown values of the result's type (an unsigned `x & (2^n - 1)` keeps it below `2^n`). |
| Enums | ⚠️ Partly | A value is not constrained to the enum's members: a property that relies on it fails with a counterexample the EVM cannot produce. |
| `bool`, `address`, `bytes1` … `bytes32`, user-defined value types | ✅ Verified | `Wei.wrap` and `Wei.unwrap` are the identity on the underlying value. |

## Mappings, arrays and structs

| Feature | Status | Notes |
|---|---|---|
| Mappings, simple and nested | ✅ Verified | Every key exists, with the zero value until written. |
| `keccak256`, `sha256`, `abi.encode`, `abi.encodePacked` | ⚠️ Partly | Uninterpreted functions: equal arguments give equal results, and nothing else is known (collisions are not excluded). They work as mapping keys, in code and in specifications. Up to 6 arguments for `abi.encode` and 4 for `abi.encodePacked`. |
| `delete` of an integer, an address or a mapping entry | ✅ Verified | Sets it to zero. |
| Fixed-size and dynamic arrays: indexing, `.length`, `push` | ✅ Verified | A fixed-size array has its declared length; `push` adds one element at the end. A memory array is a reference, as in Solidity. |
| An array index out of range | ⚠️ Partly | Not modelled as a revert: a property that relies on the index being in range fails with a counterexample the EVM cannot produce. |
| Structs | ⚠️ Partly | Copied into storage, and from storage or calldata into memory (assignments, declarations, arguments, returned values), as Solidity does; a memory-to-memory assignment shares the struct, and a function a memory struct is passed to may change its fields. A function that writes a field of a struct that is not a fresh copy reports a spurious `heap frame` failure. |
| A storage reference to a struct (`Info storage d = data;`) | ⚠️ Partly | A read through it reads the storage when it runs, so it sees later writes. A write through it is rejected: it would not reach the storage. (GAP-010) |

## Statements and expressions

| Feature | Status | Notes |
|---|---|---|
| `if`, `for`, `while`, `do`-`while`, `break`, `continue`, `return` | ✅ Verified | A loop condition is evaluated before every iteration, with its effects. |
| `require`, `assert` | ✅ Verified | A false `require` ends the path; its message is evaluated first, with its effects. `assert(c)` is an obligation. |
| Operators, `? :`, `++`, `--`, `op=`, short-circuit `&&` and &#124;&#124; | ✅ Verified | As in Solidity: `i++` yields the old value, `++i` the new one, and the right operand of `&&` and &#124;&#124; runs only when needed. |
| Tuple declarations, several return values | ✅ Verified | `(uint256 a, uint256 b) = f();` declares both for the rest of the block. |
| Identifiers starting with `$` | ✅ Verified | As OpenZeppelin 5 uses for storage pointers. |

## Transaction values

| Feature | Status | Notes |
|---|---|---|
| `msg.sender`, `msg.value` | ✅ Verified | Of type `address` and `uint256`; `msg.sender` is not the zero address. An internal function sees its caller's values. |
| `msg.sender` in a constructor | ✅ Verified | The deployer, as in any function. |
| `msg.value` in a function that is not `payable` | ⚠️ Partly | Not assumed to be 0 (Solidity reverts such a call when it carries Ether): a property that relies on it fails with a counterexample the EVM cannot produce. |
| `block.*`, `tx.*`, `msg.sig`, `msg.data`, `this` | ⚠️ Partly | One value per transaction, of its type; `block.timestamp` and `block.number` are positive. Nothing relates them across transactions (time need not increase), and an invariant may not use them. A use may print an internal `BUG:` diagnostic, which does not affect the results. (GAP-005) |
| `gasleft()`, `address.balance`, the result of `send` | ⚠️ Unknown values | A fresh value of the result's type at every read or call. |

## External calls and assembly

| Feature | Status | Notes |
|---|---|---|
| External calls and re-entrancy | ⚠️ Unknown values | A call of another contract (through an interface, `this.f()`, an external function value), a low-level `call`, or `new C(…)` may call back into the contract: its state is unknown after the call, except for the contract invariants, which an external function checks before the call and assumes after it. `view` calls and `staticcall` change nothing, nor do `send` and `transfer`; `delegatecall` may change all state, invariants included. Results are unknown values of their type. A constructor cannot be re-entered. `--assume-no-reentrancy` trusts that no call re-enters: calls other than `delegatecall` then change nothing (see [Contract Invariants](./contract_invariants.md#external-calls-and-reentrancy)). (GAP-007) |
| Inline assembly | ⚠️ Unknown values | Not interpreted. Afterwards, unknown: the Solidity variables a block assigns; every memory variable if it writes memory; all contract state (of its type) if it may write storage (`sstore`, calls). A block that may `return` or `stop` ends the transaction on some paths. Rejected: assigning a storage reference, writing memory with a memory struct in scope, and ending a constructor. |

## Results and output

| Feature | Status | Notes |
|---|---|---|
| Counterexamples | ✅ Verified | Printed under a refuted obligation (❌) when z3 gives a model: parameters, `old` state, `msg.*`, nested mapping values. |
| Unknown (❓) results | ⚠️ Partly | An obligation is unknown when its verification condition has a quantified assumption (`sum`, `forall`, a key-scoped `modifies` frame, a constructor that zero-initializes a mapping), nonlinear arithmetic, or the solver runs out of time (`--timeout`). Unknown is not a failure: the exit status is 0 unless `--strict`. (GAP-001) |
| Plain text, `--json`, `--sarif` (SARIF 2.1.0), `--pipeline-json` | ✅ Verified | See [Output Formats](./output_formats.md) and [SARIF](./sarif.md). |
| Exit status | ✅ Verified | 1 when the file cannot be translated, in every format. In plain text, 1 when an obligation is refuted or a verification error occurs, and 0 otherwise (unknown results included). With `--json`, `--sarif` or `--pipeline-json`, 0 whatever the verdicts, which the reader of the output judges. `--strict`, in every format, exits 1 also when an obligation is refuted or unknown, or an annotation or function was not verified. |
| SMT solver | ⚠️ Partly | z3, found on `PATH`; cvc5 is not supported. Results can differ between z3 versions; the test fixtures pin only results that z3 4.8.12 and 4.15.4 agree on. (GAP-012) |
<!-- capabilities:end supported -->

If something behaves differently from these pages, please open a GitHub
issue.
