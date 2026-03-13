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
from strata.base import Dialect, Program, SourceRange, StrLit, Seq, OptionArg

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
        sys.exit(EXIT_PARSE_FAILURE)
    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        print(f"solc produced invalid JSON: {exc}", file=sys.stderr)
        sys.exit(EXIT_PARSE_FAILURE)
    errors = output.get("errors", [])
    fatal = [e for e in errors if e.get("severity") == "error"]
    if fatal:
        for e in fatal:
            print(e["formattedMessage"], file=sys.stderr)
        sys.exit(EXIT_PARSE_FAILURE)
    return output


def get_ast(solc_output: dict) -> dict:
    """Extract the AST from solc standard-json output."""
    sources = solc_output.get("sources", {})
    for _name, info in sources.items():
        ast = info.get("ast")
        if ast is not None:
            return ast
    print("No AST found in solc output", file=sys.stderr)
    sys.exit(EXIT_PARSE_FAILURE)


# ---------------------------------------------------------------------------
# JSON AST → DDM Ion conversion
# ---------------------------------------------------------------------------

class Converter:
    """Converts solc JSON AST nodes to DDM Operations."""

    def __init__(self, dialect: Dialect):
        self.d = dialect

    @staticmethod
    def _source_range(node: dict) -> SourceRange | None:
        """Parse the solc `src` field (offset:length:fileIndex) into a SourceRange."""
        src = node.get("src")
        if src is None:
            return None
        parts = src.split(":")
        if len(parts) < 2:
            return None
        try:
            offset = int(parts[0])
            length = int(parts[1])
            return SourceRange(offset, offset + length)
        except (ValueError, IndexError):
            return None

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

    # Node types that carry no verification semantics and should be
    # silently dropped from sequences (e.g. NatSpec documentation).
    _SKIP_NODE_TYPES = frozenset({
        "StructuredDocumentation",
        "EventDefinition",   # Events carry no verification semantics
        "EmitStatement",     # emit is a no-op for verification
    })

    def _seq_nodes(self, nodes) -> Seq:
        if nodes is None:
            return Seq(())
        return Seq(tuple(
            self.convert_node(n) for n in nodes
            if n.get("nodeType") not in self._SKIP_NODE_TYPES
        ))

    def _seq_opt_nodes(self, nodes) -> Seq:
        """For arrays that may contain null entries (e.g. VariableDeclarationStatement.declarations)."""
        if nodes is None:
            return Seq(())
        return Seq(tuple(self._opt_node(n) for n in nodes))

    def _seq_strings(self, strings) -> Seq:
        if strings is None:
            return Seq(())
        return Seq(tuple(StrLit(s) for s in strings))

    @staticmethod
    def _doc_text(node: dict) -> str:
        """Extract NatSpec documentation text from a node, handling both old (string) and new (object) formats."""
        doc = node.get("documentation")
        if doc is None:
            return ""
        if isinstance(doc, str):
            return doc
        if isinstance(doc, dict):
            return doc.get("text", "")
        return ""

    def convert_type_name(self, node: dict) -> strata.Operation:
        nt = node.get("nodeType", "")
        ann = self._source_range(node)
        if nt == "ElementaryTypeName":
            return self.d.ElementaryTypeName(self._str(node.get("name")), ann=ann)
        if nt == "UserDefinedTypeName":
            # Extract name from nested IdentifierPath (pathNode.name)
            path_node = node.get("pathNode")
            if path_node is None:
                print("Error: UserDefinedTypeName missing pathNode", file=sys.stderr)
                sys.exit(1)
            name = path_node.get("name", "")
            if not name:
                print("Error: UserDefinedTypeName missing pathNode.name", file=sys.stderr)
                sys.exit(1)
            return self.d.UserDefinedTypeName(self._str(name), ann=ann)
        if nt == "Mapping":
            key_node = node.get("keyType")
            val_node = node.get("valueType")
            if key_node is None or val_node is None:
                print("Error: Mapping missing keyType or valueType", file=sys.stderr)
                sys.exit(1)
            return self.d.MappingType(
                self.convert_type_name(key_node),
                self.convert_type_name(val_node), ann=ann)
        if nt == "ArrayTypeName":
            base_node = node.get("baseType")
            if base_node is None:
                print("Error: ArrayTypeName missing baseType", file=sys.stderr)
                sys.exit(1)
            return self.d.ArrayTypeName(
                self.convert_type_name(base_node), ann=ann)
        # Fallback: wrap as ElementaryTypeName with the typeString
        ts = node.get("typeDescriptions", {}).get("typeString", "unknown")
        return self.d.ElementaryTypeName(self._str(ts), ann=ann)

    def convert_node(self, node: dict) -> strata.Operation:
        nt = node.get("nodeType", "")
        ann = self._source_range(node)

        if nt == "PragmaDirective":
            return self.d.PragmaDirective(
                self._seq_strings(node.get("literals")), ann=ann)

        if nt == "ContractDefinition":
            return self.d.ContractDefinition(
                self._str(node.get("name")),
                self._str(node.get("contractKind", "contract")),
                self._seq_nodes(node.get("nodes")),
                self._str(self._doc_text(node)), ann=ann)

        if nt == "ModifierDefinition":
            return self.d.ModifierDefinition(
                self._str(node.get("name", "")),
                self.convert_node(node["parameters"]),
                self._opt_node(node.get("body")), ann=ann)

        if nt == "ModifierInvocation":
            mod_name_node = node.get("modifierName", {})
            mod_name = mod_name_node.get("name", "") if isinstance(mod_name_node, dict) else str(mod_name_node)
            return self.d.ModifierInvocation(
                self._str(mod_name),
                self._seq_nodes(node.get("arguments")), ann=ann)

        if nt == "PlaceholderStatement":
            # The `_;` in modifier bodies — skip it (handled structurally)
            return self.d.ExpressionStatement(
                self.d.Literal(self._str("_"), self._str("string"), ann=ann), ann=ann)

        if nt == "FunctionDefinition":
            modifiers = node.get("modifiers", [])
            mod_nodes = Seq(tuple(self.convert_node(m) for m in modifiers))
            return self.d.FunctionDefinition(
                self._str(node.get("name", "")),
                self._str(node.get("kind", "function")),
                self._str(node.get("stateMutability", "")),
                self._str(node.get("visibility", "")),
                self.convert_node(node["parameters"]),
                self.convert_node(node["returnParameters"]),
                self._opt_node(node.get("body")),
                self._str(self._doc_text(node)),
                mod_nodes, ann=ann)

        if nt == "ParameterList":
            return self.d.ParameterList(
                self._seq_nodes(node.get("parameters", [])), ann=ann)

        if nt == "VariableDeclaration":
            return self.d.VariableDeclaration(
                self._str(node.get("name", "")),
                self._opt_type_name(node.get("typeName")),
                self._bool_str(node.get("stateVariable", False)),
                self._bool_str(node.get("constant", False)),
                self._str(node.get("storageLocation", "")), ann=ann)

        if nt == "Block":
            return self.d.Block(
                self._seq_nodes(node.get("statements", [])), ann=ann)

        if nt == "UncheckedBlock":
            return self.d.UncheckedBlock(
                self._seq_nodes(node.get("statements", [])), ann=ann)

        if nt == "ExpressionStatement":
            return self.d.ExpressionStatement(
                self.convert_node(node["expression"]), ann=ann)

        if nt == "Return":
            return self.d.Return(
                self._opt_node(node.get("expression")), ann=ann)

        if nt == "IfStatement":
            return self.d.IfStatement(
                self.convert_node(node["condition"]),
                self.convert_node(node["trueBody"]),
                self._opt_node(node.get("falseBody")), ann=ann)

        if nt == "WhileStatement":
            return self.d.WhileStatement(
                self.convert_node(node["condition"]),
                self.convert_node(node["body"]), ann=ann)

        if nt == "ForStatement":
            return self.d.ForStatement(
                self._opt_node(node.get("initializationExpression")),
                self._opt_node(node.get("condition")),
                self._opt_node(node.get("loopExpression")),
                self.convert_node(node["body"]), ann=ann)

        if nt == "VariableDeclarationStatement":
            return self.d.VariableDeclarationStatement(
                self._seq_opt_nodes(node.get("declarations", [])),
                self._opt_node(node.get("initialValue")), ann=ann)

        if nt == "Assignment":
            return self.d.Assignment(
                self.convert_node(node["leftHandSide"]),
                self.convert_node(node["rightHandSide"]),
                self._str(node.get("operator", "=")), ann=ann)

        if nt == "BinaryOperation":
            return self.d.BinaryOperation(
                self.convert_node(node["leftExpression"]),
                self.convert_node(node["rightExpression"]),
                self._str(node.get("operator")), ann=ann)

        if nt == "UnaryOperation":
            return self.d.UnaryOperation(
                self.convert_node(node["subExpression"]),
                self._str(node.get("operator")),
                self._bool_str(node.get("prefix", True)), ann=ann)

        if nt == "FunctionCall":
            return self.d.FunctionCall(
                self.convert_node(node["expression"]),
                self._seq_nodes(node.get("arguments", [])),
                self._str(node.get("kind", "functionCall")),
                self._seq_strings(node.get("names")), ann=ann)

        if nt == "Identifier":
            return self.d.Identifier(
                self._str(node.get("name")), ann=ann)

        if nt == "Literal":
            return self.d.Literal(
                self._str(node.get("value", "")),
                self._str(node.get("kind", "number")), ann=ann)

        if nt == "MemberAccess":
            return self.d.MemberAccess(
                self.convert_node(node["expression"]),
                self._str(node.get("memberName")), ann=ann)

        if nt == "IndexAccess":
            return self.d.IndexAccess(
                self.convert_node(node["baseExpression"]),
                self._opt_node(node.get("indexExpression")), ann=ann)

        if nt == "ElementaryTypeNameExpression":
            # Type conversion expression, e.g. address(0).
            # Extract the type name string from the nested typeName node.
            tn = node.get("typeName", {})
            type_name = tn.get("name", "") if isinstance(tn, dict) else str(tn)
            return self.d.ElementaryTypeNameExpression(
                self._str(type_name), ann=ann)

        if nt == "Conditional":
            return self.d.Conditional(
                self.convert_node(node["condition"]),
                self.convert_node(node["trueExpression"]),
                self.convert_node(node["falseExpression"]), ann=ann)

        if nt == "TupleExpression":
            return self.d.TupleExpression(
                self._seq_nodes(node.get("components", [])), ann=ann)

        if nt == "StructDefinition":
            return self.d.StructDefinition(
                self._str(node.get("name")),
                self._seq_nodes(node.get("members", [])), ann=ann)

        if nt == "EnumDefinition":
            return self.d.EnumDefinition(
                self._str(node.get("name")),
                self._seq_nodes(node.get("members", [])), ann=ann)

        if nt == "EnumValue":
            return self.d.EnumValue(
                self._str(node.get("name")), ann=ann)

        # Unsupported node type — fail explicitly so downstream stages
        # don't silently produce incorrect verification results.
        # TODO: consider a dedicated UnsupportedNode dialect op for
        #       partial-pipeline testing once more node types are added.
        print(f"Error: unsupported Solidity AST nodeType '{nt}'",
              file=sys.stderr)
        sys.exit(1)

    def convert_source_unit(self, ast: dict) -> strata.Operation:
        if ast.get("nodeType") != "SourceUnit":
            print(f"Expected SourceUnit, got {ast.get('nodeType')}", file=sys.stderr)
            sys.exit(1)
        ann = self._source_range(ast)
        return self.d.SourceUnit(self._seq_nodes(ast.get("nodes", [])), ann=ann)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

# Error code for sol_to_strata on parse failure.
# (reserved for future use in invoke_solc / get_ast error paths)
EXIT_PARSE_FAILURE = 100


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
