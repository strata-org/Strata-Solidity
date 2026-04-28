# Strata Solidity — Private Distribution

Formally verify Solidity smart contracts using the Strata verification framework.

## What's Included

```
StrataSolidity/
├── docs/guide/book/          ← User guide (open index.html)
├── contract-examples/        ← Example contracts with specs
├── test/                     ← Golden-file test suite
├── vscode-strata-solidity/   ← IDE extension (separate repo)
└── powers/strata/            ← Kiro Power for AI-assisted specs
```

## Quick Start

### 1. Build the verifier

Requires: Lean 4 (see `lean-toolchain`), z3, solc, Python 3.12+

```bash
cd StrataSolidity
lake build
```

### 2. Install the IDE extension

```bash
# Symlink into Kiro extensions
ln -s /path/to/vscode-strata-solidity ~/.kiro/extensions/strata-fv.vscode-strata-solidity-0.2.0

# Copy the built binary
cp StrataSolidity/.lake/build/bin/strataSolidity vscode-strata-solidity/bin/
```

Add to `~/.kiro/extensions/extensions.json`:
```json
{
  "identifier": { "id": "strata-fv.vscode-strata-solidity" },
  "version": "0.2.0",
  "location": { "$mid": 1, "path": "/path/to/vscode-strata-solidity", "scheme": "file" },
  "relativeLocation": "strata-fv.vscode-strata-solidity-0.2.0",
  "metadata": { "isBuiltin": false, "installedTimestamp": 0, "source": "gallery" }
}
```

### 3. Write specs and verify

```solidity
contract Token {
    mapping(address => uint256) public balances;
    /// @custom:strata invariant totalSupply == sum(balances)
    uint256 public totalSupply;

    /**
     * @notice Mints new tokens.
     * @custom:strata modifies balances[to], totalSupply
     * @custom:strata ensures balances[to] == old(balances[to]) + amount
     * @custom:strata ensures totalSupply == old(totalSupply) + amount
     */
    function mint(address to, uint256 amount) external {
        balances[to] += amount;
        totalSupply += amount;
    }
}
```

Save the file → verification runs automatically → results appear inline.

## What Can Be Verified

- ✅ Scalar state variables and mappings (simple, nested)
- ✅ `old()` for pre-state comparisons
- ✅ `sum(mapping)` for supply conservation
- ✅ `forall` quantifiers with `==>`
- ✅ Key-scoped `modifies` with automatic frame conditions
- ✅ Division, modulo, non-linear arithmetic
- ✅ Events, custom errors, revert statements
- ✅ Constructor invariant establishment
- ✅ Loop invariants with `old()`

## Known Limitations

- ❌ Struct fields through mappings (`mapping(k => Struct).field`)
- ❌ External calls / reentrancy
- ❌ Inheritance / virtual dispatch
- ❌ `block.timestamp`
- ❌ Inline assembly

See `docs/guide/book/` for the full user guide.

## Running Tests

```bash
# Golden-file integration tests
STRATA_VERIFY=vscode-strata-solidity/bin/strata-verify.sh bash test/run_tests.sh

# Lean unit tests
lake test
```

## Documentation

- **User Guide**: `docs/guide/book/index.html` (open in browser)
- **FAQ**: `FAQ.md`
- **Limitations**: `LIMITATIONS.md`
- **Annotation Reference**: `docs/guide/book/annotation_reference.html`
