# Running StrataSolidity

Let's verify a simple token contract. Create a file called `token.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Token {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    /// @custom:strata requires amount <= balances[msg.sender]
    /// @custom:strata ensures balances[msg.sender] == old(balances[msg.sender]) - amount
    /// @custom:strata ensures balances[to] == old(balances[to]) + amount
    /// @custom:strata modifies balances[msg.sender], balances[to]
    function transfer(address to, uint256 amount) external {
        require(amount <= balances[msg.sender], "Insufficient");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }
}
```

Run StrataSolidity:

```bash
Tools/Solidity/scripts/strata-verify.sh token.sol
```

You should see:

```
==== Contract: Token ====
  transfer:
    [line 9] precondition: ✅ pass
    [line 10] postcondition: ✅ pass
    [line 11] postcondition: ✅ pass
    [line 12] frame condition: ✅ pass
```

Every specification annotation has been mathematically proven correct.

## Introducing a bug

Now change the implementation to introduce a bug — swap the order so the addition happens first:

```solidity
function transfer(address to, uint256 amount) external {
    require(amount <= balances[msg.sender], "Insufficient");
    balances[to] += amount;           // moved up
    balances[msg.sender] -= amount;   // moved down
}
```

This is still correct for distinct addresses, but when `to == msg.sender`, the behavior changes. Re-run:

```bash
Tools/Solidity/scripts/strata-verify.sh token.sol
```

```
==== Contract: Token ====
  transfer:
    [line 10] postcondition: ❌ fail
```

StrataSolidity caught the bug — the postcondition about `balances[msg.sender]` no longer holds when `to == msg.sender`.

## Verification tools

### strata-verify.sh

The shell wrapper runs the full pipeline (parse → translate → verify) in one command:

```bash
Tools/Solidity/scripts/strata-verify.sh <file.sol> [--sarif] [--verbose]
```

### strata_verify.py

The Python wrapper supports two modes:

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
