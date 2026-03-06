#!/usr/bin/env python3
# Copyright Strata Contributors
#
#  SPDX-License-Identifier: Apache-2.0 OR MIT

"""
Solidity front-end: invoke solc --standard-json, convert AST JSON to Ion
via the DDM dialect mechanism.

Usage:
  python -m Tools.Solidity.src.solast sol_to_strata <input.sol> <output.solidity.st.ion>
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Placeholder: dialect definition and Ion serialization will be implemented
# in a subsequent task.  This file currently provides only the solc JSON
# invocation helper so that the test harness can exercise the pipeline
# end-to-end with a trivial smoke test.
# ---------------------------------------------------------------------------


def invoke_solc(sol_path: str) -> dict:
    """Run solc --standard-json and return the parsed JSON output."""
    source = Path(sol_path).read_text()
    input_json = json.dumps({
        "language": "Solidity",
        "sources": {
            sol_path: {"content": source}
        },
        "settings": {
            "outputSelection": {
                "*": {"": ["ast"]}
            }
        }
    })
    result = subprocess.run(
        ["solc", "--standard-json"],
        input=input_json,
        capture_output=True,
        text=True,
    )
    # solc --standard-json returns 0 even on compilation errors, reporting
    # them in the JSON output instead.  A non-zero exit code indicates an
    # infrastructure-level failure (e.g. binary crash, bad JSON input).
    if result.returncode != 0:
        print(f"solc exited with code {result.returncode}:\n{result.stderr}",
              file=sys.stderr)
        sys.exit(1)
    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        print(f"solc produced invalid JSON: {exc}", file=sys.stderr)
        sys.exit(1)
    errors = output.get("errors", [])
    fatal = [e for e in errors if e.get("severity") == "error"]
    if fatal:
        for e in fatal:
            print(e["formattedMessage"], file=sys.stderr)
        sys.exit(1)
    return output


def sol_to_strata(sol_path: str, output_path: str) -> None:
    """Convert a .sol file to Ion binary via solc JSON AST.

    Currently a stub — writes the solc AST JSON to output_path.
    Full Ion serialization will be added in a follow-up task.
    """
    output = invoke_solc(sol_path)
    sources = output.get("sources", {})
    for _name, info in sources.items():
        ast = info.get("ast")
        if ast is not None:
            Path(output_path).write_text(json.dumps(ast, indent=2) + "\n")
            return
    print("No AST found in solc output", file=sys.stderr)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Solidity to Strata Ion converter")
    sub = parser.add_subparsers(dest="command")

    p_convert = sub.add_parser("sol_to_strata", help="Convert .sol to .solidity.st.ion")
    p_convert.add_argument("sol_file", help="Input Solidity file")
    p_convert.add_argument("output", help="Output Ion file")

    args = parser.parse_args()
    if args.command == "sol_to_strata":
        sol_to_strata(args.sol_file, args.output)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
