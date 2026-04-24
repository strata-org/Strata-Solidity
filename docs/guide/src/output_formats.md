# Output Formats

StrataSolidity supports two output formats: plain text (default) and SARIF.

## Plain text (default)

Per-assertion results with source locations:

```
==== Contract: Token ====
  mint:
    [line 8] postcondition: ✅ pass
  transfer:
    [line 14] precondition: ✅ pass
    [line 16] postcondition: ❌ fail
```

Each specification annotation is reported individually with its result:
- ✅ **pass** — the property was mathematically proven.
- ❌ **fail** — the property could not be proven (possible bug or insufficient specification).
- ❓ **unknown** — the solver could not determine the result within its limits.

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
