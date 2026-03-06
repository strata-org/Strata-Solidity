#!/usr/bin/env python3
# Copyright Strata Contributors
#
#  SPDX-License-Identifier: Apache-2.0 OR MIT

"""
Solidity front-end: invoke solc --standard-json, convert AST JSON to Ion
via the DDM dialect mechanism.

Usage:
  python3 -m Tools.Solidity.src.solast dialect <output_dir>
  python3 -m Tools.Solidity.src.solast sol_to_strata [--dialect <path>] <input.sol> <output.ion>
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

# Ensure strata.base is importable
_tools_python = Path(__file__).resolve().parent.parent.parent / "Python"
if str(_tools_python) not in sys.path:
    sys.path.insert(0, str(_tools_python))

import amazon.ion.simpleion as ion
import strata.base as strata
from strata.base import Dialect, Program, StrLit, Seq, OptionArg

from .base_dialect import gen_dialect


# ---------------------------------------------------------------------------
# solc invocation
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


def get_ast(solc_output: dict) -> dict:
    """Extract the AST from solc standard-json output."""
    sources = solc_output.get("sources", {})
    for _name, info in sources.items():
        ast = info.get("ast")
        if ast is not None:
            return ast
    print("No AST found in solc output", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# JSON AST → DDM Ion conversion
# ---------------------------------------------------------------------------

class Converter:
    """Converts solc JSON AST nodes to DDM Operations."""

    def __init__(self, dialect: Dialect):
        self.d = dialect

    def _str(self, v) -> StrLit:
        return StrLit(str(v) if v is not None else "")

    def _bool_str(self, v) -> StrLit:
        return StrLit("true" if v else "false")

    def _opt_node(self, node) -> strata.Arg:
        if node is None:
            return self.d.missing_node()
        return self.d.some_node(self.convert_node(node))

    def _opt_type_name(self, node) -> strata.Arg:
        if node is None:
            return self.d.missing_type_name()
        return self.d.some_type_name(self.convert_type_name(node))

    def _seq_nodes(self, nodes) -> Seq:
        if nodes is None:
            return Seq(())
        return Seq(tuple(self.convert_node(n) for n in nodes))

    def _seq_opt_nodes(self, nodes) -> Seq:
        """For arrays that may contain null entries (e.g. VariableDeclarationStatement.declarations)."""
        if nodes is None:
            return Seq(())
        return Seq(tuple(self._opt_node(n) for n in nodes))

    def _seq_strings(self, strings) -> Seq:
        if strings is None:
            return Seq(())
        return Seq(tuple(StrLit(s) for s in strings))

    def convert_type_name(self, node: dict) -> strata.Operation:
        nt = node.get("nodeType", "")
        if nt == "ElementaryTypeName":
            return self.d.ElementaryTypeName(self._str(node.get("name")))
        # Fallback: wrap as ElementaryTypeName with the typeString
        ts = node.get("typeDescriptions", {}).get("typeString", "unknown")
        return self.d.ElementaryTypeName(self._str(ts))

    def convert_node(self, node: dict) -> strata.Operation:
        nt = node.get("nodeType", "")

        if nt == "PragmaDirective":
            return self.d.PragmaDirective(
                self._seq_strings(node.get("literals")))

        if nt == "ContractDefinition":
            return self.d.ContractDefinition(
                self._str(node.get("name")),
                self._str(node.get("contractKind", "contract")),
                self._seq_nodes(node.get("nodes")))

        if nt == "FunctionDefinition":
            return self.d.FunctionDefinition(
                self._str(node.get("name", "")),
                self._str(node.get("kind", "function")),
                self._str(node.get("stateMutability", "")),
                self._str(node.get("visibility", "")),
                self.convert_node(node["parameters"]),
                self.convert_node(node["returnParameters"]),
                self._opt_node(node.get("body")))

        if nt == "ParameterList":
            return self.d.ParameterList(
                self._seq_nodes(node.get("parameters", [])))

        if nt == "VariableDeclaration":
            return self.d.VariableDeclaration(
                self._str(node.get("name", "")),
                self._opt_type_name(node.get("typeName")),
                self._bool_str(node.get("stateVariable", False)),
                self._bool_str(node.get("constant", False)))

        if nt == "Block":
            return self.d.Block(
                self._seq_nodes(node.get("statements", [])))

        if nt == "ExpressionStatement":
            return self.d.ExpressionStatement(
                self.convert_node(node["expression"]))

        if nt == "Return":
            return self.d.Return(
                self._opt_node(node.get("expression")))

        if nt == "IfStatement":
            return self.d.IfStatement(
                self.convert_node(node["condition"]),
                self.convert_node(node["trueBody"]),
                self._opt_node(node.get("falseBody")))

        if nt == "WhileStatement":
            return self.d.WhileStatement(
                self.convert_node(node["condition"]),
                self.convert_node(node["body"]))

        if nt == "VariableDeclarationStatement":
            return self.d.VariableDeclarationStatement(
                self._seq_opt_nodes(node.get("declarations", [])),
                self._opt_node(node.get("initialValue")))

        if nt == "Assignment":
            return self.d.Assignment(
                self.convert_node(node["leftHandSide"]),
                self.convert_node(node["rightHandSide"]),
                self._str(node.get("operator", "=")))

        if nt == "BinaryOperation":
            return self.d.BinaryOperation(
                self.convert_node(node["leftExpression"]),
                self.convert_node(node["rightExpression"]),
                self._str(node.get("operator")))

        if nt == "UnaryOperation":
            return self.d.UnaryOperation(
                self.convert_node(node["subExpression"]),
                self._str(node.get("operator")),
                self._bool_str(node.get("prefix", True)))

        if nt == "FunctionCall":
            return self.d.FunctionCall(
                self.convert_node(node["expression"]),
                self._seq_nodes(node.get("arguments", [])),
                self._str(node.get("kind", "functionCall")))

        if nt == "Identifier":
            return self.d.Identifier(
                self._str(node.get("name")))

        if nt == "Literal":
            return self.d.Literal(
                self._str(node.get("value", "")),
                self._str(node.get("kind", "number")))

        if nt == "MemberAccess":
            return self.d.MemberAccess(
                self.convert_node(node["expression"]),
                self._str(node.get("memberName")))

        if nt == "IndexAccess":
            return self.d.IndexAccess(
                self.convert_node(node["baseExpression"]),
                self._opt_node(node.get("indexExpression")))

        # Unsupported node type — emit as Identifier with the nodeType as name
        # so the pipeline doesn't crash on unknown nodes.
        print(f"Warning: unsupported nodeType '{nt}', emitting as Identifier",
              file=sys.stderr)
        return self.d.Identifier(self._str(f"__unsupported_{nt}__"))

    def convert_source_unit(self, ast: dict) -> strata.Operation:
        assert ast.get("nodeType") == "SourceUnit"
        return self.d.SourceUnit(self._seq_nodes(ast.get("nodes", [])))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

# Error code for sol_to_strata on parse failure.
exit_parse_failure = 100


def write_dialect(dialect: Dialect, dir_path: Path):
    dir_path.mkdir(parents=True, exist_ok=True)
    output = dir_path / f"{dialect.name}.dialect.st.ion"
    with output.open("wb") as w:
        ion.dump(dialect.to_ion(), w, binary=True)
    print(f"Wrote {dialect.name} dialect to {output}")


def solidity_dialect(path: str | None) -> Dialect:
    if path is None:
        return gen_dialect()
    with open(path, "rb") as f:
        return Dialect.from_ion(f)


def sol_to_strata_imp(args):
    dialect = solidity_dialect(args.dialect)
    converter = Converter(dialect)

    sol_path = args.sol_file
    solc_output = invoke_solc(sol_path)
    ast = get_ast(solc_output)

    prog = Program(dialect)
    prog.add(converter.convert_source_unit(ast))

    with open(args.output, "wb") as w:
        ion.dump(prog.to_ion(), w, binary=True)


def main():
    parser = argparse.ArgumentParser(
        prog="solast",
        description="Solidity to Strata Ion converter")
    sub = parser.add_subparsers(dest="command")

    # dialect subcommand
    p_dialect = sub.add_parser("dialect", help="Write Solidity DDM dialect to directory.")
    p_dialect.add_argument("output_dir", help="Directory to write dialect to.")

    # sol_to_strata subcommand
    p_convert = sub.add_parser("sol_to_strata", help="Convert .sol to .solidity.st.ion")
    p_convert.add_argument("--dialect", help="File to read Solidity dialect from.")
    p_convert.add_argument("sol_file", help="Input Solidity file")
    p_convert.add_argument("output", help="Output Ion file")

    args = parser.parse_args()
    if args.command == "dialect":
        write_dialect(gen_dialect(), Path(args.output_dir))
    elif args.command == "sol_to_strata":
        sol_to_strata_imp(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
