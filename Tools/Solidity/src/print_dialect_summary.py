#!/usr/bin/env python3
# Copyright Strata Contributors
#
#  SPDX-License-Identifier: Apache-2.0 OR MIT
"""
Print a structural summary of the Python-defined Solidity DDM dialect
(`Tools/Solidity/src/base_dialect.py:gen_dialect()`).

Output format matches `lake exe gen-dialect-summary` exactly: line-oriented,
sorted by declaration name, with the same `op`/`syncat`/`type` keywords and
the same `Name : Category (arg1, arg2, …)` shape.

Used by the dialect-parity CI check (Group A step 3): the Python summary
and the Lean summary must diff cleanly. Any drift between
`base_dialect.py` and `StrataSolidity/SolidityDialectLean.lean` produces a
diff and fails the build.

Usage:
  python3 Tools/Solidity/src/print_dialect_summary.py
  python3 Tools/Solidity/src/print_dialect_summary.py > /tmp/python-dialect.txt
"""

import sys
from pathlib import Path

# Ensure strata.base is importable. Path mirrors solast.py:
#   <repo>/Strata/Tools/Python is on sys.path so that `import strata.base` works.
_repo_root = Path(__file__).resolve().parent.parent.parent.parent
_strata_python = _repo_root / "Strata" / "Tools" / "Python"
if str(_strata_python) not in sys.path:
    sys.path.insert(0, str(_strata_python))

# `base_dialect` lives in the same directory as this script.
sys.path.insert(0, str(Path(__file__).resolve().parent))

import strata.base as strata  # noqa: E402
from base_dialect import gen_dialect  # noqa: E402


def _format_syncat(decl) -> str:
    return f"syncat {decl.name}"


def _format_op(op, dialect_alias: str) -> str:
    """Match the Lean summary's `op Name : Category (a, b, c)` shape.

    The Lean side names its dialect `SolidityLean` for namespace
    separation from the Ion-loaded `Solidity`; we substitute the
    Python-side dialect name with `dialect_alias` so the two summaries
    diff cleanly.
    """
    args = ", ".join(arg.name for arg in op.args)
    cat = str(op.result).replace(f"{op.dialect}.", f"{dialect_alias}.", 1)
    return f"op {op.name} : {cat} ({args})"


def main() -> int:
    # Default to the Lean-side dialect alias so `diff` against
    # `lake exe gen-dialect-summary` is clean. Override with --as=<name>
    # if you want the Python-canonical `Solidity.<cat>` form.
    dialect_alias = "SolidityLean"
    for arg in sys.argv[1:]:
        if arg.startswith("--as="):
            dialect_alias = arg[len("--as="):]

    d = gen_dialect()

    lines: list[str] = []
    for decl in d.decls:
        cls_name = type(decl).__name__
        if cls_name == "SynCatDecl":
            lines.append(_format_syncat(decl))
        elif cls_name == "OpDecl":
            lines.append(_format_op(decl, dialect_alias))
        # Ignore any other declaration kinds (the Lean summary does the same).

    lines.sort()

    print("# Solidity dialect — structural summary")
    print(f"# Generated from Tools/Solidity/src/base_dialect.py")
    print(f"# {len(lines)} total declarations")
    print()
    for line in lines:
        print(line)

    return 0


if __name__ == "__main__":
    sys.exit(main())
