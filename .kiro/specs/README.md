# StrataSolidity Specifications

This directory hosts the canonical specifications for StrataSolidity. It is an
**index** only — the specs themselves are the source of truth. Do not duplicate
their content here.

## Two-spec model

StrataSolidity uses a paired spec layout:

- **`strata-solidity-baseline/`** — a **frozen, descriptive** retrospective
  baseline that pins today's behavior on `main`. It introduces no new
  functionality. Every supported Solidity construct, annotation, CLI flag,
  output format, test harness, and known limitation is recorded with a stable
  ID so downstream work can cite it unambiguously. The baseline is tagged
  (`v0.1.0-baseline`) and is amended only for documentation or
  property-based-test drift, never for feature changes.

- **`strata-solidity-next/`** — the forward-looking spec that **diffs against
  the baseline**. It is the **only** place where `GAP-*` items are allowed to
  close. Any new requirement must cite the `REQ-*` or `GAP-*` IDs it touches
  and must leave every other baseline requirement unchanged.

Contributors adding features should read `strata-solidity-baseline/requirements.md`
and `strata-solidity-baseline/design.md` first, then open or extend
`strata-solidity-next/` rather than editing the baseline.

## Stable ID scheme

Every acceptance criterion in the baseline carries an ID from one of the
following namespaces. IDs are stable across the lifetime of the baseline and
are safe to cite from code comments, tests, and follow-on specs.

| Prefix         | Scope                                                                         |
| -------------- | ----------------------------------------------------------------------------- |
| `REQ-STRATA-*` | Contract with the vendored `Strata` git submodule                              |
| `REQ-SOL-*`    | Supported Solidity subset accepted by the translator                          |
| `REQ-SPEC-*`   | `@custom:strata` specification annotation language                            |
| `REQ-PIPE-*`   | Pipeline stages (AST ingest → Laurel → Core → VCG → SMT)                      |
| `REQ-CLI-*`    | `strataSolidity` CLI binary surface (flags, exit codes, output selection)     |
| `REQ-SH-*`     | Shell wrappers (`strata-verify.sh`, `run_sol_analyze_laurel.sh`, harnesses)   |
| `REQ-PY-*`     | Python tooling under `Tools/Solidity/` (notably `solast.py`)                  |
| `REQ-OUT-*`    | Output formats (human, `--json`, `--pipeline-json`, SARIF 2.1.0)              |
| `REQ-TEST-*`   | Test harnesses, golden tests, benchmark harness, XFAIL set                   |
| `REQ-DIST-*`   | Distribution, packaging, and published documentation                          |
| `GAP-*`        | Tracked gaps bridging the baseline to `strata-solidity-next`                  |
| `REQ-PBT-*`    | Property-based-test characterization contracts that pin baseline behavior     |

`REQ-PBT-*` IDs are characterization contracts: they do not add behavior, they
fence today's behavior against silent regression from `strata-solidity-next`.

## Layout

```
.kiro/specs/
├── README.md                        ← this index (orientation only)
├── strata-solidity-baseline/
│   ├── requirements.md              ← frozen baseline (REQ-*, GAP-*, REQ-PBT-*)
│   ├── design.md                    ← architecture and risk register
│   └── tasks.md                     ← retrospective implementation plan
└── strata-solidity-next/            ← forward-looking, diffs against baseline
```
