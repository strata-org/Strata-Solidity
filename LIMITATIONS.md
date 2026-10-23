# Strata Solidity — Current Limitations

## Counterexamples and `unknown` results

**Status:** Partially supported

Refuted obligations are reported as failed (❌) with a counterexample
(`a = 0`, `b = 1`, …) whenever z3 can produce a model. Since the 2026-10
Strata re-pin, mappings are encoded with SMT array theory, each function is
verified in its own SMT context, and values carry their Solidity type
ranges, so most false properties come with concrete values.

An obligation is still reported as `unknown` (❓, exit 0) when its
verification condition contains a universally quantified assumption, because
z3's model-based quantifier instantiation (MBQI) is off. The remaining
sources are:

- `sum(m)` specs: the sum update axiom is quantified (only for mappings that
  some annotation sums);
- constructors that zero-initialize a mapping (Core axiomatizes `mapConst`
  with a quantifier);
- quantified specs (`forall`) and key-scoped `modifies` frames;
- nonlinear arithmetic and solver timeouts (`--timeout=<s>`).

`--no-array-theory` restores the older encoding, under which far more
results are `unknown`.

---

## Struct Fields Through Mappings

**Status:** Not supported  
**Tracking:** [Asana P0](https://app.asana.com/1/8442528107068/project/1213978144576593/task/1214065007095245)

Specs cannot reference struct fields accessed through mapping values.

```solidity
// ❌ NOT SUPPORTED
struct Payment { uint256 amount; bool captured; }
mapping(bytes32 => Payment) public payments;

/// @custom:strata ensures payments[id].amount == amt
```

The Laurel translation is correct, but Strata Core's heap parameterization cannot resolve struct field names through composite types.

**Affected patterns:**
- `mapping(key => Struct)` with `.field` access in specs
- Staking contracts (`stakers[msg.sender].stakedAmount`)
- Vault contracts with per-user position structs
- Any DeFi protocol with complex per-user/per-position state

**Workaround:** Flatten structs into separate mappings:

```solidity
// ✅ SUPPORTED — flatten the struct
mapping(bytes32 => uint256) public paymentAmounts;
mapping(bytes32 => bool) public paymentCaptured;

/// @custom:strata ensures paymentAmounts[id] == amt
```

This is not practical for verifying existing contracts but works for new designs.

---

## Supported Patterns (what works today)

| Pattern | Example | Status |
|---|---|---|
| Simple mapping | `balances[msg.sender]` | ✅ |
| Nested mapping | `allowance[from][spender]` | ✅ |
| Nested mapping with `old()` | `old(allowance[from][msg.sender])` | ✅ |
| Mapping-only contract (no scalars) | Contract with only `mapping` state vars | ✅ |
| Scalar state vars | `uint256 totalSupply` | ✅ |
| `old()` on scalars and mappings | `old(totalSupply)`, `old(balances[addr])` | ✅ |
| `forall` quantifier with `==>` | `forall addr : address :: addr != msg.sender ==> ...` | ✅ |
| Key-scoped `modifies` | `modifies balances[msg.sender]` | ✅ |
| Frame conditions (scalar) | Undeclared scalar writes caught | ✅ |
| Frame conditions (mapping key) | Undeclared writes to other keys caught | ✅ |
| Function call as mapping key | `data[keccak256(abi.encodePacked(a, b))]` | ✅ |
| `msg.sender`, `msg.value` | Used as keys or in expressions | ✅ |
| `address(0)`, type conversions | Truncate as the EVM does (`uint8(x)`, `int8(u)`, `bytes4(h)` keeps the high bytes); widening keeps the value | ✅ |
| `type(uint256).max/min` | Compile-time constants | ✅ |
| Arithmetic | `+`, `-`, `*`, `/`, `%`; `unchecked` wraps; signed `/`, `%` round toward zero, in specifications too; constant expressions have solc's exact value; constant `**` folded; bitwise results stay in their type | ✅ (checked overflow is not modelled as a revert: properties relying on it may not be proven) |
| Unary operators in specs | `!paused`, negative literals (`-887272`) | ✅ |
| Named constants in specs | `requires status == NOT_ENTERED`, `modifies roles[DEFAULT_ADMIN_ROLE]` | ✅ |
| Subdenominations | `1 ether`, `2 days` folded to base units | ✅ |
| In-contract invariants | `invariant` attached to a state variable's NatSpec | ✅ |
| Return value + `modifies` | `returns (uint256)` with mapping-state outputs | ✅ |
| Comparisons | `==`, `!=`, `>=`, `<=`, `>`, `<` | ✅ |
| Boolean logic | `&&`, `\|\|`, `==>` | ✅ |
| `requires` / `ensures` | Pre/postconditions | ✅ |
| `invariant` | Contract-level invariants checked on all functions | ✅ |
| `modifies` | Field-level and key-scoped frame conditions | ✅ |
| Modifiers | Inlined into each function using them, with arguments; `return` in the body still runs the code after `_` | ✅ (not modifiers of an imported base contract, which are reported) |
| Struct assignments | Copied into storage, and from storage or calldata into memory (assignments, declarations, arguments, returned values); memory-to-memory assignments share the struct, and a function a memory struct is passed to may change its fields | ✅ (a function writing a struct that is not a copy it made reports a spurious `heap frame` failure) |

## Not Yet Supported

| Pattern | Status | Notes |
|---|---|---|
| Struct fields through mappings | ❌ Blocked (Core) | See above |
| `old()` in loop invariants | ❌ Blocked (Core) | `__old` marker not resolved in loop context |
| `@custom:strata lemma` | ❌ Not started | Needs Laurel grammar extension |
| `block.*`, `tx.*`, `msg.sig` | ✅ Modelled | Fixed for the transaction (two reads agree) and of their Solidity type; `block.timestamp` and `block.number` are positive. Not allowed in invariants, nor are `msg.sender` and `msg.value`: they change between transactions |
| `gasleft()`, balances, `send` | ⚠️ Unknown | A fresh value of the result type at every read or call |
| `msg.sender` in constructor | ❌ | Constructor handling incomplete |
| External calls / reentrancy | ⚠️ Havoc | A call of another contract (through an interface, `this.f()`, an external function value), a low-level `call`, or `new C(…)` may call back into the contract: its state is unknown after the call, except for the contract invariants, which an external function checks before the call and assumes after it. `view` calls and `staticcall` change nothing; nor do `send` and `transfer` (too little gas to). `delegatecall` may change all state, invariants included. Results are unknown values of their type. Constructors cannot be re-entered. `--assume-no-reentrancy` trusts that no call re-enters: calls (other than `delegatecall`) then change nothing |
| Assembly / inline Yul | ⚠️ Havoc | Not interpreted. Afterwards, unknown: the Solidity variables a block assigns; every memory variable if it writes memory; all contract state (of its type) if it may write storage (`sstore`, calls). A block that may `return` or `stop` ends the transaction on some paths, as `selfdestruct` does. Rejected: assigning a storage reference, writing memory with a memory struct in scope, ending a constructor, and calling a function that may end the transaction (the code after the call would be verified as if it ran) |
| Dynamic arrays (push/pop) | ⚠️ Partial | `.length` and `push` work; `pop` not modeled |
| Inheritance | ⚠️ Partial | Single contract only, no virtual dispatch |
| Events / errors | First-class ops | `revert` prunes its path; `emit` is a verification no-op |

## Storage References

**Status:** Partially supported

Storage references to struct fields through mappings (`Voter storage sender = voters[addr]`) are not supported — blocked by the same struct-through-mapping limitation.

Mapping storage references (`mapping(...) storage ref = stateVar`) are not supported.

A mapping or array `storage` parameter (`function _credit(mapping(address => uint256) storage m, address k)`)
is rejected: it refers to the caller's storage, and the translator models
parameters as local copies, so a write through it would not reach the state
variable passed in.

A storage reference to a struct state variable (`Info storage d = data;`)
can be read: a read `d.value` reads the storage of `data` when it runs, so
it sees writes made after the reference was taken, directly or by a call.
Writing through it (`d.value = 5`) is rejected: the write would not reach
the storage.

Direct state variable access without storage references works fully.
