# Output Formats

StrataSolidity has four output formats: plain text (the default), `--json`, `--sarif` and `--pipeline-json`. When more than one is given, `--sarif` takes precedence over `--json`. Warnings (annotations or functions that are not verified, and why) go to standard error in every format.

## Plain text (default)

Obligations are grouped by result (verification errors first, then failures, unknown results and passes), each with the source location of the annotation it checks, followed by a summary line:

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
- ✅ **pass** — the property was proven.
- ❌ **fail** — the solver refuted the property: some input and state violate it (a bug, or a specification that needs a precondition). When the solver returns a model, the values of the counterexample are printed indented beneath the obligation.
- ❓ **unknown** — the solver could neither prove nor refute the property within its limits. This is common for properties that depend on quantified axioms (see [Current Limitations](./limitations.md)).
- ⚠ **error** — the solver could not run on the obligation (for example, z3 is not on the `PATH`); these are listed first, under `⚠ Errors`, and counted in the summary line.

When some annotations or functions were not verified, a last line says how many (`⚠  2 annotation(s) or function(s) not verified (see warnings)`).

In plain text, the command exits with status 1 when an obligation fails or a verification error occurs; `unknown` results do not by themselves cause a non-zero exit. With `--json`, `--sarif` or `--pipeline-json` it exits with status 0 whatever the results, which the reader of the output judges. Pass `--strict`, in any format, to exit with status 1 when an obligation fails or is unknown, or an annotation or function was not verified. A file that cannot be translated exits with status 1 in every format.

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

## `--pipeline-json`

Pass `--pipeline-json` for one JSON object with what each stage produced:
the generated Laurel (`laurel`) and Core (`core`) programs, the obligations
with their status and the SMT file each was checked with (`obligations`),
the summary counts (`summary`), and the warnings (`warnings`). It is meant
for debugging the translation and for tools.

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
