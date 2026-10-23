# Current Limitations

What StrataSolidity does not verify, or verifies only in part, by area.
What it verifies as Solidity runs it is on [Supported
Features](./supported_features.md). Both pages are generated from the
capability ledger (`docs/capabilities.toml` in the repository), whose
entries name the tests that show them.

The statuses:

<!-- capabilities:begin statuses -->
<!-- Generated from docs/capabilities.toml by scripts/capabilities.py: edit the ledger, then run the script. -->
- ✅ **Verified**: modelled as Solidity runs it. A true property can be proven; a false one is refuted or not proven.
- ⚠️ **Partly**: modelled, except for what the notes say.
- ⚠️ **Unknown values**: not interpreted. What it may change or return is unknown afterwards: a property that depends on it is not proven, and nothing false is proven either.
- ⚠️ **Not verified**: skipped, with a warning. The rest of the file is verified.
- ❌ **Rejected**: the translation stops with an error that says why. Nothing in the file is verified.
- ❌ **Fails**: valid Solidity on which the translation stops with an internal error. Nothing in the file is verified.
<!-- capabilities:end statuses -->

<!-- capabilities:begin limitations -->
<!-- Generated from docs/capabilities.toml by scripts/capabilities.py: edit the ledger, then run the script. -->
## Specifications

| Feature | Status | Notes |
|---|---|---|
| `msg.sender`, `msg.value`, `block.*` or `tx.*` in an invariant | ❌ Rejected | They change between transactions, so an invariant over them would be established with one transaction's values and assumed with another's. |
| `modifies m[a][b]` (a key with two indexes) | ⚠️ Not verified | The key cannot be read, so the frame of `m` is not checked (a warning says so). With one index, `modifies m[a]` allows every `m[a][…]` to change. |
| A loop that writes contract state | ⚠️ Partly | The function's `heap frame (only this contract is modified)` obligation is unknown (❓): the loop does not keep the fact that only this contract's state changes. Its invariants and postconditions are checked as usual. Writing a local in the loop, and the state after it, avoids this. |
| `exists v : T :: P` | ⚠️ Partly | `v` ranges over the values of `T`. z3 does not search for witnesses, so a true `exists` is often unknown (❓); it is proven when the witness is at hand (a value the function wrote). |
| `**`, bitwise and shift operators in specifications | ❌ Rejected | Not part of the specification language: the translation stops with "Unexpected tokens after spec expression". |
| Type conversions in specifications (`uint8(x)`) | ❌ Fails | `address(x)` is accepted (it is the identity); other conversions stop the translation. In code, conversions work. |
| Misspelled, misplaced or multi-line annotations | ⚠️ Not verified | Reported and ignored, never dropped silently: an unknown keyword, an annotation where it has no effect, in a plain `//` comment, inside a function body, in the middle of a comment line, or continued on the next line. |
| `@custom:strata lemma` | ⚠️ Not verified | Not an annotation StrataSolidity reads: reported as unrecognized, and ignored. (GAP-004) |

## Contracts and functions

| Feature | Status | Notes |
|---|---|---|
| Overloads that differ only between integer and address parameters (`f(uint256)`, `f(address)`) | ❌ Fails | Both kinds are integers in the translation, so the two functions get the same signature ("Duplicate definition"). |
| `revert("reason")`, `revert()` | ❌ Fails | Use `require(condition, "reason")` or a custom error. |
| A constructor that calls an internal function using state (`_mint` in a constructor) | ❌ Rejected | The constructor has no state to pass to the callee yet. |
| Calling a function that may end the transaction (`selfdestruct`, assembly `return` or `stop`) | ❌ Rejected | The code after such a call would be verified as if it always ran. In the function itself, a halt ends its path. |
| Library calls (`L.f(x)`, `using L for T`) | ❌ Fails | A library function called from a contract is not found. |
| Functions declared outside a contract | ❌ Fails | Not verified (a warning says so), and a call of one stops the translation. |

## Inheritance

| Feature | Status | Notes |
|---|---|---|
| Base constructor arguments in an inheritance specifier (`is Base(7)`) | ⚠️ Unknown values | Not read (the AST the translator receives does not keep them): the base constructor runs with unknown values of its parameter types. (GAP-009) |
| `super.f(…)` or `Base.f(…)` of an overloaded function | ❌ Rejected | The call is not resolved to one of the overloads. (GAP-009) |
| A base contract from another file | ⚠️ Not verified | Its state, functions and invariants are not part of what is verified, for each contract that inherits it, directly or through another base (a warning says so). (GAP-009) |
| A base's private state variable declared again in a derived contract | ❌ Rejected | They are different variables, which the translation would merge. (GAP-009) |

## Types and arithmetic

| Feature | Status | Notes |
|---|---|---|
| Checked arithmetic (outside `unchecked`) | ⚠️ Partly | Computed on unbounded integers: an overflow is not modelled as a revert, so the verifier also considers the execution continuing with the out-of-range value. That only adds behaviors: a property that relies on the revert may not be proven (see [Integers](./integers.md)). |
| `**` with an operand that is not a constant | ❌ Rejected | `x ** 2` can be written `x * x`. |
| Bitwise operators and shifts | ⚠️ Partly | `~` and shifts by a constant are exact; `&`, &#124;, `^` and shifts by a variable are unknown values of the result's type (an unsigned `x & (2^n - 1)` keeps it below `2^n`). |
| Enums | ⚠️ Partly | A value is not constrained to the enum's members: a property that relies on it fails with a counterexample the EVM cannot produce. |
| `string` and dynamic `bytes` values | ❌ Fails | A local, `.length` or a conversion such as `bytes(s)` stops the translation; a parameter that is only passed on (to an event, say) works. |

## Mappings, arrays and structs

| Feature | Status | Notes |
|---|---|---|
| `keccak256`, `sha256`, `abi.encode`, `abi.encodePacked` | ⚠️ Partly | Uninterpreted functions: equal arguments give equal results, and nothing else is known (collisions are not excluded). They work as mapping keys, in code and in specifications. Up to 6 arguments for `abi.encode` and 4 for `abi.encodePacked`. |
| `abi.encodeWithSelector` or `abi.encodeWithSignature` with arguments, `abi.encodeCall`, `abi.decode`, more arguments than above | ❌ Fails | The function is not defined in the translation. |
| `delete` of a `bool`, an array or a struct | ❌ Fails | The translation assigns `0`, which has the wrong type. |
| An array index out of range | ⚠️ Partly | Not modelled as a revert: a property that relies on the index being in range fails with a counterexample the EVM cannot produce. |
| `pop()` | ❌ Fails | Not modelled. (GAP-008) |
| `push` on an array in a mapping or a struct, or through a returned storage reference | ❌ Fails | Only `push` on an array state variable is modelled. |
| `.length` of a memory array created with `new` | ❌ Fails | Creating it works. |
| Structs | ⚠️ Partly | Copied into storage, and from storage or calldata into memory (assignments, declarations, arguments, returned values), as Solidity does; a memory-to-memory assignment shares the struct, and a function a memory struct is passed to may change its fields. A function that writes a field of a struct that is not a fresh copy reports a spurious `heap frame` failure. |
| A struct built with positional arguments (`Info(1, 2)`) | ❌ Fails | The named form `Info({a: 1, b: 2})` works. |
| Struct-valued mappings and arrays of structs | ⚠️ Not verified | A function or constructor that uses one is not verified, and neither is an annotation on a struct field through a mapping (`payments[id].amount`); warnings say so. Separate mappings per field work instead. (GAP-002) |
| A modifier that uses a struct-valued mapping | ❌ Fails | Unlike a function, which is skipped, it stops the translation. (GAP-002) |
| A storage reference to a struct (`Info storage d = data;`) | ⚠️ Partly | A read through it reads the storage when it runs, so it sees later writes. A write through it is rejected: it would not reach the storage. (GAP-010) |
| A storage reference to a mapping or an array | ❌ Rejected | "storage reference must have a user-defined struct type". (GAP-010) |
| A mapping or array `storage` parameter | ❌ Rejected | It refers to the caller's storage, and a write through it would not reach the variable passed in. |

## Statements and expressions

| Feature | Status | Notes |
|---|---|---|
| An `if`/`else` or `try`/`catch` whose branches end with assignments of different types | ❌ Fails | "'if' branches have incompatible types". Branches that end with assignments of the same type work. |
| An operand that changes a variable another operand reads (`_inc() + x`) | ❌ Rejected | solc's code generators evaluate operands in different orders. |
| Assigning a tuple to existing variables (`(a, b) = (b, a)`) | ❌ Rejected | A tuple declaration works. |
| A parameter or local named `result` in a function whose return value is unnamed | ❌ Fails | The translation names that return value `result` too. Naming the return value avoids it. |

## Transaction values

| Feature | Status | Notes |
|---|---|---|
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
| Unknown (❓) results | ⚠️ Partly | An obligation is unknown when its verification condition has a quantified assumption (`sum`, `forall`, a key-scoped `modifies` frame, a constructor that zero-initializes a mapping), nonlinear arithmetic, or the solver runs out of time (`--timeout`). Unknown is not a failure: the exit status is 0 unless `--strict`. (GAP-001) |
| SMT solver | ⚠️ Partly | z3, found on `PATH`; cvc5 is not supported. Results can differ between z3 versions; the test fixtures pin only results that z3 4.8.12 and 4.15.4 agree on. (GAP-012) |
<!-- capabilities:end limitations -->

## Workaround: struct fields through mappings

A function that uses a struct-valued mapping is not verified. Flattening
the struct into one mapping per field makes it verifiable:

```solidity
struct Payment { uint256 amount; bool captured; }
mapping(bytes32 => Payment) public payments;

/// @custom:strata ensures payments[id].amount == amt  // not verified
```

```solidity
mapping(bytes32 => uint256) public paymentAmounts;
mapping(bytes32 => bool) public paymentCaptured;

/// @custom:strata ensures paymentAmounts[id] == amt  // verified
```
