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

      # --strict exits 1 unless every obligation is proven and every
      # annotation was verified; the SARIF is written either way.
      - name: Run StrataSolidity
        run: |
          Tools/Solidity/scripts/strata-verify.sh contracts/Token.sol --sarif --strict > results.sarif

      - name: Upload SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: results.sarif
```

Without `--strict`, `--sarif` exits 0 whatever the results: the
machine-readable formats leave the verdict to their consumer.

## Results

Every obligation is one SARIF result, located at the annotation, statement
or expression it checks:

| Outcome | `kind` | `level` |
|---|---|---|
| proven | `pass` | `none` |
| refuted (with a counterexample when z3 produces one) | `fail` | `error` |
| unknown — neither proven nor refuted, including solver timeouts | `fail` | `warning` |
| verification error (encoding error, solver crash), rule `strata/tool-error` | `fail` | `error` |
| annotation or function not verified, rule `strata/not-verified` | `fail` | `warning` |

The rule (`strata/ensures-fail`, `strata/requires-fail`,
`strata/invariant-fail`, `strata/frame-fail`, `strata/loop-invariant-fail`,
`strata/division-by-zero`, `strata/assert-fail`, …) names the kind of
property; the message names the property itself (`ensures totalSupply ==
old(totalSupply) + amount: fail`). `partialFingerprints.obligationId/v2`
identifies a result across unrelated edits.

## VS Code

Install the [SARIF Viewer](https://marketplace.visualstudio.com/items?itemName=MS-SarifVSCode.sarif-viewer) extension. Open a `.sarif` file and verification results appear inline in the editor — similar to compiler diagnostics.
