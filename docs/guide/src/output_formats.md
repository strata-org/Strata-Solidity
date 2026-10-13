# Output Formats

StrataSolidity supports three output formats: plain text (default), `--json`, and `--sarif`. When more than one flag is given, `--sarif` takes precedence over `--json`.

## Plain text (default)

Obligations are grouped by status, each with the source location of the annotation it checks, followed by a summary line:

```
==== Verification Results ====
❓ Unknown (2):
  invariant totalSupply == sum(balances) at line 13, col 5
  ensures totalSupply == old(totalSupply) + amount at line 12, col 9

✅ Passed (8):
  invariant totalSupply == sum(balances) at line 4, col 1
  modifies frame (balances) at line 13, col 5
  ensures balances[to] == old(balances[to]) + amount at line 11, col 9
  ...

8 passed, 0 failed, 2 unknown out of 10 total
```

Each proof obligation is reported individually with its result:
- ✅ **pass** — the property was mathematically proven.
- ❌ **fail** — the property could not be proven (possible bug or insufficient specification). When the solver returns a counterexample model, each variable's value is printed indented beneath the obligation.
- ❓ **unknown** — the solver could neither prove nor refute the property within its limits. This is common for properties that depend on quantified axioms (see [Current Limitations](./limitations.md)).

The command exits with status 1 when any obligation fails or a verification error occurs; `unknown` results do not by themselves cause a non-zero exit. Pass `--strict` to also fail when any obligation is unproven or any annotation went unverified.

## `--json`

Pass `--json` for a flat array of results, convenient for scripting:

```bash
Tools/Solidity/scripts/strata-verify.sh contract.sol --json
```

```json
[{"name": "assert(359)", "description": "ensures totalSupply == old(totalSupply) + amount", "status": "pass", "line": 12, "col": 9},
 {"name": "assert(285)", "description": "ensures balances[to] == old(balances[to]) + amount", "status": "pass", "line": 11, "col": 9}]
```

Annotations or functions the translator could not verify are appended with `"status": "not_verified"`.

## SARIF

Pass `--sarif` to get machine-readable [SARIF 2.1.0](https://sarifweb.azurewebsites.net/) JSON output:

```bash
Tools/Solidity/scripts/strata-verify.sh contract.sol --sarif
```

SARIF is the Static Analysis Results Interchange Format — a standard consumed by:
- **GitHub Code Scanning** — upload SARIF to see verification results as code annotations in pull requests.
- **VS Code** — the [SARIF Viewer](https://marketplace.visualstudio.com/items?itemName=MS-SarifVSCode.sarif-viewer) extension renders results inline with squiggly underlines.
- **CI/CD pipelines** — any tool that consumes SARIF can process StrataSolidity output.

See [CI Integration (SARIF)](./sarif.md) for details on integrating with CI pipelines.
