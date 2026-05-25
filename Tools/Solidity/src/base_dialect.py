# Copyright Strata Contributors
#
#  SPDX-License-Identifier: Apache-2.0 OR MIT

"""
DDM dialect definition for Solidity AST nodes (Phase 1).

Defines one DDM operation per solc AST nodeType, following the pattern
in Tools/Python/strata/pythonast.py.  The dialect is consumed by both
the Python serializer (solast.py) and the Lean reader (ReadSolidity.lean).
"""

import sys
from pathlib import Path

# Add the Python tools directory so we can import strata.base
_tools_python = Path(__file__).resolve().parent.parent.parent / "Python"
if str(_tools_python) not in sys.path:
    sys.path.insert(0, str(_tools_python))

import strata.base as strata
from strata.base import ArgDecl, Init


def gen_dialect() -> strata.Dialect:
    """Create the Solidity DDM dialect for Phase 1 AST nodes."""
    Sol = strata.Dialect("Solidity")
    Sol.add_import("Init")

    # -- Syntax categories --
    Sol.add_syncat("node")          # generic AST node
    Sol.add_syncat("opt_node")      # optional node
    Sol.add_syncat("type_name")     # type name nodes
    Sol.add_syncat("opt_type_name") # optional type name

    # Optional node wrappers
    Sol.add_op("some_node", ArgDecl("x", Sol.node()), Sol.opt_node())
    Sol.add_op("missing_node", Sol.opt_node())
    Sol.add_op("some_type_name", ArgDecl("x", Sol.type_name()), Sol.opt_type_name())
    Sol.add_op("missing_type_name", Sol.opt_type_name())

    # -- Top-level --
    Sol.add_op("SourceUnit",
        ArgDecl("nodes", Init.Seq(Sol.node())),
        Init.Command())

    Sol.add_op("PragmaDirective",
        ArgDecl("literals", Init.Seq(Init.Str())),
        Sol.node())

    Sol.add_op("ContractDefinition",
        ArgDecl("name", Init.Str()),
        ArgDecl("contractKind", Init.Str()),
        ArgDecl("nodes", Init.Seq(Sol.node())),
        ArgDecl("documentation", Init.Str()),
        ArgDecl("baseContracts", Init.Seq(Init.Str())),
        Sol.node())

    # -- Modifiers --
    Sol.add_op("ModifierDefinition",
        ArgDecl("name", Init.Str()),
        ArgDecl("parameters", Sol.node()),
        ArgDecl("body", Sol.opt_node()),
        Sol.node())

    Sol.add_op("ModifierInvocation",
        ArgDecl("modifierName", Init.Str()),
        ArgDecl("arguments", Init.Seq(Sol.node())),
        Sol.node())

    # -- Functions --
    Sol.add_op("FunctionDefinition",
        ArgDecl("name", Init.Str()),
        ArgDecl("kind", Init.Str()),
        ArgDecl("stateMutability", Init.Str()),
        ArgDecl("visibility", Init.Str()),
        ArgDecl("parameters", Sol.node()),
        ArgDecl("returnParameters", Sol.node()),
        ArgDecl("body", Sol.opt_node()),
        ArgDecl("documentation", Init.Str()),
        ArgDecl("modifiers", Init.Seq(Sol.node())),
        Sol.node())

    Sol.add_op("ParameterList",
        ArgDecl("parameters", Init.Seq(Sol.node())),
        Sol.node())

    Sol.add_op("VariableDeclaration",
        ArgDecl("name", Init.Str()),
        ArgDecl("typeName", Sol.opt_type_name()),
        ArgDecl("stateVariable", Init.Str()),
        ArgDecl("constant", Init.Str()),
        ArgDecl("storageLocation", Init.Str()),
        ArgDecl("value", Sol.opt_node()),
        ArgDecl("documentation", Init.Str()),
        Sol.node())

    # -- Statements --
    Sol.add_op("Block",
        ArgDecl("statements", Init.Seq(Sol.node())),
        Sol.node())

    Sol.add_op("UncheckedBlock",
        ArgDecl("statements", Init.Seq(Sol.node())),
        Sol.node())

    Sol.add_op("ExpressionStatement",
        ArgDecl("expression", Sol.node()),
        Sol.node())

    Sol.add_op("Return",
        ArgDecl("expression", Sol.opt_node()),
        Sol.node())

    Sol.add_op("IfStatement",
        ArgDecl("condition", Sol.node()),
        ArgDecl("trueBody", Sol.node()),
        ArgDecl("falseBody", Sol.opt_node()),
        Sol.node())

    Sol.add_op("WhileStatement",
        ArgDecl("condition", Sol.node()),
        ArgDecl("body", Sol.node()),
        Sol.node())

    Sol.add_op("ForStatement",
        ArgDecl("initializationExpression", Sol.opt_node()),
        ArgDecl("condition", Sol.opt_node()),
        ArgDecl("loopExpression", Sol.opt_node()),
        ArgDecl("body", Sol.node()),
        Sol.node())

    Sol.add_op("VariableDeclarationStatement",
        ArgDecl("declarations", Init.Seq(Sol.opt_node())),
        ArgDecl("initialValue", Sol.opt_node()),
        Sol.node())

    Sol.add_op("InlineAssembly",
        ArgDecl("yul", Init.Str()),
        Sol.node())

    # -- Expressions --
    Sol.add_op("Assignment",
        ArgDecl("leftHandSide", Sol.node()),
        ArgDecl("rightHandSide", Sol.node()),
        ArgDecl("operator", Init.Str()),
        Sol.node())

    Sol.add_op("BinaryOperation",
        ArgDecl("leftExpression", Sol.node()),
        ArgDecl("rightExpression", Sol.node()),
        ArgDecl("operator", Init.Str()),
        Sol.node())

    Sol.add_op("UnaryOperation",
        ArgDecl("subExpression", Sol.node()),
        ArgDecl("operator", Init.Str()),
        ArgDecl("prefix", Init.Str()),
        Sol.node())

    Sol.add_op("FunctionCall",
        ArgDecl("expression", Sol.node()),
        ArgDecl("arguments", Init.Seq(Sol.node())),
        ArgDecl("kind", Init.Str()),
        ArgDecl("names", Init.Seq(Init.Str())),
        Sol.node())

    Sol.add_op("Identifier",
        ArgDecl("name", Init.Str()),
        Sol.node())

    Sol.add_op("Literal",
        ArgDecl("value", Init.Str()),
        ArgDecl("kind", Init.Str()),
        Sol.node())

    Sol.add_op("MemberAccess",
        ArgDecl("expression", Sol.node()),
        ArgDecl("memberName", Init.Str()),
        Sol.node())

    Sol.add_op("IndexAccess",
        ArgDecl("baseExpression", Sol.node()),
        ArgDecl("indexExpression", Sol.opt_node()),
        Sol.node())

    # -- Ternary / tuple expressions --
    Sol.add_op("Conditional",
        ArgDecl("condition", Sol.node()),
        ArgDecl("trueExpression", Sol.node()),
        ArgDecl("falseExpression", Sol.node()),
        Sol.node())

    Sol.add_op("TupleExpression",
        ArgDecl("components", Init.Seq(Sol.node())),
        Sol.node())

    # -- Type conversion expressions --
    Sol.add_op("ElementaryTypeNameExpression",
        ArgDecl("typeName", Init.Str()),
        Sol.node())

    # -- Events and errors --
    Sol.add_op("EventDefinition",
        ArgDecl("name", Init.Str()),
        ArgDecl("parameters", Sol.node()),
        ArgDecl("anonymous", Init.Str()),
        Sol.node())

    Sol.add_op("ErrorDefinition",
        ArgDecl("name", Init.Str()),
        ArgDecl("parameters", Sol.node()),
        Sol.node())

    Sol.add_op("EmitStatement",
        ArgDecl("eventCall", Sol.node()),
        Sol.node())

    Sol.add_op("RevertStatement",
        ArgDecl("errorCall", Sol.node()),
        Sol.node())

    # -- Structs --
    Sol.add_op("StructDefinition",
        ArgDecl("name", Init.Str()),
        ArgDecl("members", Init.Seq(Sol.node())),
        Sol.node())

    # -- Enums --
    Sol.add_op("EnumDefinition",
        ArgDecl("name", Init.Str()),
        ArgDecl("members", Init.Seq(Sol.node())),
        Sol.node())

    Sol.add_op("EnumValue",
        ArgDecl("name", Init.Str()),
        Sol.node())

    # -- Type names --
    Sol.add_op("ElementaryTypeName",
        ArgDecl("name", Init.Str()),
        Sol.type_name())

    Sol.add_op("UserDefinedTypeName",
        ArgDecl("name", Init.Str()),
        Sol.type_name())

    Sol.add_op("MappingType",
        ArgDecl("keyType", Sol.type_name()),
        ArgDecl("valueType", Sol.type_name()),
        Sol.type_name())

    Sol.add_op("ArrayTypeName",
        ArgDecl("baseType", Sol.type_name()),
        Sol.type_name())

    return Sol
