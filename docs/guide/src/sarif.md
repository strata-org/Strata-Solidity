# CI Integration (SARIF)

StrataSolidity's SARIF output enables integration with CI/CD pipelines. Verification results appear as code annotations alongside your existing linting and testing checks.

## GitHub Actions

Upload SARIF results to GitHub Code Scanning. StrataSolidity is built from
source, so the job checks it out (with its Strata submodule), builds it,
and installs solc and z3:

```yaml
name: Verify Contracts
on: [push, pull_request]

permissions:
  contents: read
  security-events: write   # upload-sarif needs it

jobs:
  verify:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4

      - name: Check out StrataSolidity
        uses: actions/checkout@v4
        with:
          repository: strata-org/Strata-Solidity
          path: strata-solidity
          submodules: recursive

      - name: Build StrataSolidity
        uses: leanprover/lean-action@v1
        with:
          lake-package-directory: strata-solidity
          build: true
          test: false
          lint: false

      - name: Install solc and z3
        run: |
          sudo add-apt-repository -y ppa:ethereum/ethereum
          sudo apt-get update
          sudo apt-get install -y solc z3

      # --strict exits 1 unless every obligation is proven and every
      # annotation was verified. results.sarif is kept only if the run
      # wrote a document (not, say, when solc is missing).
      - name: Run StrataSolidity
        run: |
          status=0
          strata-solidity/Tools/Solidity/scripts/strata-verify.sh contracts/Token.sol --sarif --strict > out.sarif || status=$?
          if [ -s out.sarif ]; then mv out.sarif results.sarif; fi
          exit $status

      - name: Upload SARIF
        if: always() && hashFiles('results.sarif') != ''
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: results.sarif
```

Building Strata from scratch takes a while: cache `strata-solidity/.lake`
and `strata-solidity/Strata/.lake` between runs, as this repository's
`.github/workflows/ci.yml` does.

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
