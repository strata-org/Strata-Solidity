# Strata Solidity — Current Limitations

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
| `address(0)`, type casts | `address(expr)` treated as identity | ✅ |
| `type(uint256).max/min` | Compile-time constants | ✅ |
| Arithmetic | `+`, `-`, `*` in specs | ✅ |
| Comparisons | `==`, `!=`, `>=`, `<=`, `>`, `<` | ✅ |
| Boolean logic | `&&`, `\|\|`, `==>` | ✅ |
| `requires` / `ensures` | Pre/postconditions | ✅ |
| `invariant` | Contract-level invariants checked on all functions | ✅ |
| `modifies` | Field-level and key-scoped frame conditions | ✅ |

## Not Yet Supported

| Pattern | Status | Notes |
|---|---|---|
| Struct fields through mappings | ❌ Blocked (Core) | See above |
| `old()` in loop invariants | ❌ Blocked (Core) | `__old` marker not resolved in loop context |
| `@custom:strata lemma` | ❌ Not started | Needs Laurel grammar extension |
| `block.timestamp` | ❌ Not modeled | No time abstraction yet |
| `msg.sender` in constructor | ❌ | Constructor handling incomplete |
| External calls / reentrancy | ❌ | No cross-contract reasoning |
| Assembly / inline Yul | ❌ | Not parsed |
| Dynamic arrays (push/pop) | ⚠️ Partial | `.length` works, push/pop not modeled |
| Inheritance | ⚠️ Partial | Single contract only, no virtual dispatch |
| Events / errors | Ignored | No effect on verification |
