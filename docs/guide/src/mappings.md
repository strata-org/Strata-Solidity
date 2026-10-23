# Mappings

Mappings are the primary data structure in Solidity smart contracts. StrataSolidity has strong support for reasoning about mappings, including simple mappings, nested mappings, and mappings with computed keys.

## Simple mappings

```solidity
mapping(address => uint256) public balances;

/// @custom:strata ensures balances[to] == old(balances[to]) + amount
function mint(address to, uint256 amount) external {
    balances[to] += amount;
}
```

Mapping access in specifications uses the same syntax as Solidity: `balances[key]`.

## Nested mappings

Nested mappings (e.g., ERC20 allowances) are supported:

```solidity
mapping(address => mapping(address => uint256)) public allowance;

/// @custom:strata requires allowance[from][msg.sender] >= amount
/// @custom:strata ensures allowance[from][msg.sender] == old(allowance[from][msg.sender]) - amount
/// @custom:strata modifies allowance[from], balances[from], balances[to]
function transferFrom(address from, address to, uint256 amount) external {
    require(allowance[from][msg.sender] >= amount, "Allowance exceeded");
    allowance[from][msg.sender] -= amount;
    balances[from] -= amount;
    balances[to] += amount;
}
```

A key-scoped `modifies` names one index: `modifies allowance[from]` allows
every `allowance[from][…]` to change, and no other row. A key with two
indexes, such as `modifies allowance[from][msg.sender]`, is not read: the
frame of `allowance` is then not checked at all, and a warning says so.

## Computed keys

Mappings keyed by hash functions are supported — `keccak256` and `sha256` are modeled as uninterpreted functions:

```solidity
mapping(bytes32 => uint256) public data;

/// @custom:strata ensures data[keccak256(abi.encodePacked(a, b))] == value
function store(address a, uint256 b, uint256 value) external {
    data[keccak256(abi.encodePacked(a, b))] = value;
}
```

The verifier treats `keccak256` as a function that is consistent (same input → same output) but otherwise uninterpreted — it does not reason about the hash algorithm itself.

## Mapping semantics

Solidity mappings have infinite domain with default zero values — every key "exists" and maps to zero until explicitly set. StrataSolidity models this using SMT arrays with `select`/`store` operations, which faithfully captures this semantics.

## Current limitation: struct-valued mappings

A function that uses a struct-valued mapping (or an array of structs) is
**not verified**, and neither is an annotation that reads a struct field
through a mapping; warnings say so:

```solidity
struct Payment { uint256 amount; bool captured; }
mapping(bytes32 => Payment) public payments;

/// @custom:strata ensures payments[id].amount == amt  // ❌ not verified
```

**Workaround:** Flatten structs into separate mappings:

```solidity
mapping(bytes32 => uint256) public paymentAmounts;
mapping(bytes32 => bool) public paymentCaptured;

/// @custom:strata ensures paymentAmounts[id] == amt  // ✅ verified
```

See [Current Limitations](./limitations.md) for details.
