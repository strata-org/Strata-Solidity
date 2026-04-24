# CI Integration (SARIF)

StrataSolidity's SARIF output enables integration with CI/CD pipelines. Verification results appear as code annotations alongside your existing linting and testing checks.

## GitHub Actions

Upload SARIF results to GitHub Code Scanning:

```yaml
name: Verify Contracts
on: [push, pull_request]

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run StrataSolidity
        run: |
          Tools/Solidity/scripts/strata-verify.sh contracts/Token.sol --sarif > results.sarif

      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: results.sarif
```

Verification failures appear as code scanning alerts on the pull request, with source locations pointing to the failing specification.

## Standard-JSON mode

For integration with existing Solidity toolchains, use the solc-compatible standard-JSON interface:

```bash
echo '{
  "language": "Solidity",
  "sources": {
    "Token.sol": { "content": "..." }
  },
  "settings": {
    "modelChecker": { "engine": "strata" }
  }
}' | python3 -m src.strata_verify
```

Returns solc-compatible JSON with verification results in the `errors` array, making it a drop-in addition to existing build pipelines that already process solc output.

## VS Code

Install the [SARIF Viewer](https://marketplace.visualstudio.com/items?itemName=MS-SarifVSCode.sarif-viewer) extension. Open a `.sarif` file and verification results appear inline in the editor — similar to compiler diagnostics.
