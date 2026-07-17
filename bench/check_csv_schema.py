# Copyright Strata Contributors
#
#  SPDX-License-Identifier: Apache-2.0 OR MIT

#!/usr/bin/env python3
"""check_csv_schema.py — Validate bench/results.csv against REQ-PBT-008.

Realizes: REQ-PBT-008
Validates: REQ-TEST-032, REQ-TEST-033, REQ-TEST-034

This post-processor is invoked from the tail of ``bench/bench.sh`` after the
harness writes ``bench/results.csv``. It asserts the CSV conforms to the schema
defined in the Strata-Solidity baseline requirements:

  * REQ-TEST-032: the first line equals the literal header
      ``benchmark,functions,specs,state_vars,mappings,status,time_ms,pass,fail,unknown,total``
  * REQ-TEST-033: every data row contains exactly 11 comma-separated fields
  * REQ-TEST-034: the ``status`` column value is one of ``{ok, error, timeout}``

Exit code is 0 when the CSV conforms; any violation causes a non-zero exit with
a clear diagnostic that cites the offending line number and the violated
requirement ID.

Note: the checker coexists with the embedded-newline fix tracked as task 3.1
(REQ-TEST-036). Once 3.1 lands, rows where ``state_vars`` previously carried
multi-line ``grep -c`` output will collapse to a single row with 11 fields and
this checker will pass. Until then, the checker is the enforcement mechanism
that surfaces the defect as a non-zero exit.
"""

from __future__ import annotations

import csv
import os
import sys
from typing import List, Sequence, TextIO

EXPECTED_HEADER: str = (
    "benchmark,functions,specs,state_vars,mappings,"
    "status,time_ms,pass,fail,unknown,total"
)
EXPECTED_FIELDS: List[str] = EXPECTED_HEADER.split(",")
EXPECTED_FIELD_COUNT: int = len(EXPECTED_FIELDS)  # 11
VALID_STATUS: frozenset = frozenset({"ok", "error", "timeout"})


def _default_csv_path() -> str:
    """Return the default path ``<script_dir>/results.csv``."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(script_dir, "results.csv")


def _emit(stream: TextIO, msg: str) -> None:
    stream.write(msg)
    if not msg.endswith("\n"):
        stream.write("\n")


def check_csv_schema(
    path: str,
    *,
    out: TextIO | None = None,
    err: TextIO | None = None,
) -> int:
    """Validate ``path`` against the REQ-PBT-008 schema.

    Returns 0 on success, non-zero on the first class of violation encountered
    (header mismatch, field count, or bad status). All violations found are
    reported before returning non-zero so a single run surfaces every problem.
    """
    out = out if out is not None else sys.stdout
    err = err if err is not None else sys.stderr

    if not os.path.isfile(path):
        _emit(err, f"ERROR [REQ-PBT-008]: CSV not found at {path!r}")
        return 2

    violations = 0

    # Read the first physical line verbatim to validate the literal header.
    # Using the raw first line (rather than a csv.reader row join) guarantees
    # byte-for-byte comparison against REQ-TEST-032, independent of how the
    # csv module would re-serialize the header.
    with open(path, "r", encoding="utf-8", newline="") as fh:
        try:
            first_line = next(fh)
        except StopIteration:
            _emit(err, "ERROR [REQ-TEST-032]: CSV is empty (line 1: missing header)")
            return 1

        header_line = first_line.rstrip("\r\n")
        if header_line != EXPECTED_HEADER:
            _emit(
                err,
                "ERROR [REQ-TEST-032] line 1: header mismatch\n"
                f"  expected: {EXPECTED_HEADER!r}\n"
                f"  actual:   {header_line!r}",
            )
            violations += 1

    # Second pass: use csv.reader so a legitimately quoted field containing
    # a comma or embedded newline is counted as one field. The embedded-newline
    # artifact noted in REQ-TEST-036 is unquoted, so csv.reader will (correctly)
    # split it across physical lines and the field-count check below will flag
    # the resulting short rows — which is exactly the behavior task 3.1 fixes.
    with open(path, "r", encoding="utf-8", newline="") as fh:
        reader = csv.reader(fh)
        status_idx = EXPECTED_FIELDS.index("status")
        for lineno, row in enumerate(reader, start=1):
            if lineno == 1:
                # Header row already validated above; skip the reader's view.
                continue
            if len(row) != EXPECTED_FIELD_COUNT:
                _emit(
                    err,
                    f"ERROR [REQ-TEST-033] line {lineno}: expected "
                    f"{EXPECTED_FIELD_COUNT} fields, got {len(row)}: {row!r}",
                )
                violations += 1
                # Skip the status check when the row is malformed; the index
                # may be out of range or point at the wrong column.
                continue
            status = row[status_idx]
            if status not in VALID_STATUS:
                _emit(
                    err,
                    f"ERROR [REQ-TEST-034] line {lineno}: status {status!r} "
                    f"not in {{ok, error, timeout}}",
                )
                violations += 1

    if violations == 0:
        _emit(out, f"OK [REQ-PBT-008]: {path} conforms to the benchmark CSV schema")
        return 0
    _emit(err, f"FAIL [REQ-PBT-008]: {violations} schema violation(s) in {path}")
    return 1


def main(argv: Sequence[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]
    if len(args) > 1:
        _emit(
            sys.stderr,
            "usage: check_csv_schema.py [RESULTS_CSV]\n"
            "       (defaults to <script_dir>/results.csv)",
        )
        return 2
    path = args[0] if args else _default_csv_path()
    return check_csv_schema(path)


if __name__ == "__main__":
    sys.exit(main())
