# Vendored JSON schemas

This directory contains third-party JSON schemas vendored locally so the
characterization test harness (`Tools/Solidity/test/`) does not depend on
network access at test time.

## `sarif-schema-2.1.0.json`

- **Standard:** OASIS Static Analysis Results Interchange Format (SARIF)
  Version 2.1.0.
- **Source:** `https://docs.oasis-open.org/sarif/sarif/v2.1.0/cs01/schemas/sarif-schema-2.1.0.json`
  (Committee Specification 01, equivalent to the
  `oasis-tcs/sarif-spec` `Schemata/sarif-schema-2.1.0.json` file).
- **Why vendored:** `test/test_sarif_schema.py` (REQ-PBT-004) validates the
  StrataSolidity `--sarif` output against this schema; pinning a local copy
  keeps the test deterministic and offline.
- **Update policy:** this baseline is frozen. Do not update the schema
  without a corresponding change in `strata-solidity-next`.
