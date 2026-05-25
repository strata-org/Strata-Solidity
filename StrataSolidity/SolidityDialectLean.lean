/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/
module

public import Strata.DDM.AST
public import Strata.DDM.BuiltinDialects.Init
import Strata.DDM.BuiltinDialects.BuiltinM

/-!
# Solidity DDM dialect — Lean source of truth (Group A)

Lean equivalent of `Tools/Solidity/src/base_dialect.py`'s `gen_dialect()`.
This file defines the Solidity DDM dialect as a Lean value, eliminating the
need to read it from a precompiled Ion artifact at compile time.

## Why

Per `.kiro/specs/pipeline-language-rationalization/` (Group A, REQ-LCD-*):
- The dialect's *consumer* is Lean. Defining it in Lean removes a Python
  dependency and a serialization round-trip on the verification path.
- Adding a new AST node becomes a single edit here, not a Python edit + an
  Ion regeneration step.
- Lean's type system makes the schema readable top-to-bottom.

## Structure

Mirrors `base_dialect.py` line-for-line:
  1. Four syntax categories: `node`, `opt_node`, `type_name`, `opt_type_name`.
  2. Four optional-wrapper ops: `some_node`, `missing_node`,
     `some_type_name`, `missing_type_name`.
  3. ~30 AST node ops grouped by area: top-level, modifiers, functions,
     statements, expressions, structs/enums, type names.

## Compatibility check

A future commit will add a `lake gen-dialect` script that serializes
`soliditydialectLean` to binary Ion via Strata's encoder, then a CI check
that the result is byte-identical to the existing
`Tools/Solidity/dialects/Solidity.dialect.st.ion` (per REQ-LCD-005).
Once parity is established, `SolidityDialect.lean` can drop `#load_dialect`
and import this file directly (REQ-LCD-014).
-/

open Strata Strata.Elab

public section
namespace Strata.Solidity

/-! ## Helper builders for terse op declarations.

We use the BuiltinM API (mirroring `Strata/DDM/BuiltinDialects/Init.lean`).
The original Python uses an `Sol.add_op(name, args..., return_cat)` shape
where each arg is `ArgDecl(name, type)`. Below, `mkOp` reproduces that
ergonomically: it takes a return category, an op name, and an array of
`(arg_name, arg_kind)` pairs.
-/

private def mkArg (name : String) (k : ArgDeclKind) : ArgDecl :=
  { ident := name, kind := k }

/-- Local syntactic-category atoms (mirrors Python's `Sol.<cat>()`). -/
private def Node     : SyntaxCat := .atom .none q`SolidityLean.node
private def OptNode  : SyntaxCat := .atom .none q`SolidityLean.opt_node
private def TypeName : SyntaxCat := .atom .none q`SolidityLean.type_name
private def OptType  : SyntaxCat := .atom .none q`SolidityLean.opt_type_name

/-- `Init.Str()` from Python — atomic string. -/
private def Str : SyntaxCat := .atom .none q`Init.Str

/-- `Init.Seq(c)` — a sequence of category `c`. -/
private def Seq (c : SyntaxCat) : SyntaxCat := SyntaxCat.mkSeq c

/-- `Init.Command()` — top-level command return category. -/
private def Command : SyntaxCat := .atom .none q`Init.Command

/-- Convenience: `mkOp returnCat name args` is the Lean equivalent of
    `Sol.add_op(name, ArgDecl(...), ..., returnCat)` from `base_dialect.py`. -/
private def mkOp (returnCat : QualifiedIdent) (name : String) (args : Array ArgDecl)
    : BuiltinM Unit := do
  declareOp {
    name      := name,
    argDecls  := { toArray := args },
    category  := returnCat,
    syntaxDef := default
  }

/-- The Lean-canonical Solidity DDM dialect. Mirrors
    `Tools/Solidity/src/base_dialect.py:gen_dialect()` line-for-line. -/
def soliditydialectLean : Strata.Dialect := BuiltinM.create! "SolidityLean" #[initDialect] do
  -- Syntax categories
  declareCat q`SolidityLean.node
  declareCat q`SolidityLean.opt_node
  declareCat q`SolidityLean.type_name
  declareCat q`SolidityLean.opt_type_name

  -- Optional-node wrappers
  mkOp q`SolidityLean.opt_node "some_node"
    #[mkArg "x" (.cat Node)]
  mkOp q`SolidityLean.opt_node "missing_node" #[]
  mkOp q`SolidityLean.opt_type_name "some_type_name"
    #[mkArg "x" (.cat TypeName)]
  mkOp q`SolidityLean.opt_type_name "missing_type_name" #[]

  -- Top-level
  mkOp q`Init.Command "SourceUnit"
    #[mkArg "nodes" (.cat (Seq Node))]

  mkOp q`SolidityLean.node "PragmaDirective"
    #[mkArg "literals" (.cat (Seq Str))]

  mkOp q`SolidityLean.node "ContractDefinition"
    #[mkArg "name" (.cat Str),
      mkArg "contractKind" (.cat Str),
      mkArg "nodes" (.cat (Seq Node)),
      mkArg "documentation" (.cat Str),
      mkArg "baseContracts" (.cat (Seq Str))]

  -- Modifiers
  mkOp q`SolidityLean.node "ModifierDefinition"
    #[mkArg "name" (.cat Str),
      mkArg "parameters" (.cat Node),
      mkArg "body" (.cat OptNode)]

  mkOp q`SolidityLean.node "ModifierInvocation"
    #[mkArg "modifierName" (.cat Str),
      mkArg "arguments" (.cat (Seq Node))]

  -- Functions
  mkOp q`SolidityLean.node "FunctionDefinition"
    #[mkArg "name" (.cat Str),
      mkArg "kind" (.cat Str),
      mkArg "stateMutability" (.cat Str),
      mkArg "visibility" (.cat Str),
      mkArg "parameters" (.cat Node),
      mkArg "returnParameters" (.cat Node),
      mkArg "body" (.cat OptNode),
      mkArg "documentation" (.cat Str),
      mkArg "modifiers" (.cat (Seq Node))]

  mkOp q`SolidityLean.node "ParameterList"
    #[mkArg "parameters" (.cat (Seq Node))]

  mkOp q`SolidityLean.node "VariableDeclaration"
    #[mkArg "name" (.cat Str),
      mkArg "typeName" (.cat OptType),
      mkArg "stateVariable" (.cat Str),
      mkArg "constant" (.cat Str),
      mkArg "storageLocation" (.cat Str),
      mkArg "value" (.cat OptNode),
      mkArg "documentation" (.cat Str)]

  -- Statements
  mkOp q`SolidityLean.node "Block"
    #[mkArg "statements" (.cat (Seq Node))]

  mkOp q`SolidityLean.node "UncheckedBlock"
    #[mkArg "statements" (.cat (Seq Node))]

  mkOp q`SolidityLean.node "ExpressionStatement"
    #[mkArg "expression" (.cat Node)]

  mkOp q`SolidityLean.node "Return"
    #[mkArg "expression" (.cat OptNode)]

  mkOp q`SolidityLean.node "IfStatement"
    #[mkArg "condition" (.cat Node),
      mkArg "trueBody" (.cat Node),
      mkArg "falseBody" (.cat OptNode)]

  mkOp q`SolidityLean.node "WhileStatement"
    #[mkArg "condition" (.cat Node),
      mkArg "body" (.cat Node)]

  mkOp q`SolidityLean.node "ForStatement"
    #[mkArg "initializationExpression" (.cat OptNode),
      mkArg "condition" (.cat OptNode),
      mkArg "loopExpression" (.cat OptNode),
      mkArg "body" (.cat Node)]

  mkOp q`SolidityLean.node "DoWhileStatement"
    #[mkArg "condition" (.cat Node),
      mkArg "body" (.cat Node)]

  mkOp q`SolidityLean.node "BreakStatement" #[]

  mkOp q`SolidityLean.node "ContinueStatement" #[]

  mkOp q`SolidityLean.node "TryStatement"
    #[mkArg "externalCall" (.cat Node),
      mkArg "clauses" (.cat (Seq Node))]

  mkOp q`SolidityLean.node "TryCatchClause"
    #[mkArg "errorName" (.cat Str),
      mkArg "parameters" (.cat OptNode),
      mkArg "block" (.cat Node)]

  mkOp q`SolidityLean.node "VariableDeclarationStatement"
    #[mkArg "declarations" (.cat (Seq OptNode)),
      mkArg "initialValue" (.cat OptNode)]

  mkOp q`SolidityLean.node "InlineAssembly"
    #[mkArg "yul" (.cat Str)]

  -- Expressions
  mkOp q`SolidityLean.node "Assignment"
    #[mkArg "leftHandSide" (.cat Node),
      mkArg "rightHandSide" (.cat Node),
      mkArg "operator" (.cat Str)]

  mkOp q`SolidityLean.node "BinaryOperation"
    #[mkArg "leftExpression" (.cat Node),
      mkArg "rightExpression" (.cat Node),
      mkArg "operator" (.cat Str)]

  mkOp q`SolidityLean.node "UnaryOperation"
    #[mkArg "subExpression" (.cat Node),
      mkArg "operator" (.cat Str),
      mkArg "prefix" (.cat Str)]

  mkOp q`SolidityLean.node "FunctionCall"
    #[mkArg "expression" (.cat Node),
      mkArg "arguments" (.cat (Seq Node)),
      mkArg "kind" (.cat Str),
      mkArg "names" (.cat (Seq Str))]

  mkOp q`SolidityLean.node "FunctionCallOptions"
    #[mkArg "expression" (.cat Node),
      mkArg "names" (.cat (Seq Str)),
      mkArg "options" (.cat (Seq Node))]

  mkOp q`SolidityLean.node "NewExpression"
    #[mkArg "typeName" (.cat TypeName)]

  mkOp q`SolidityLean.node "Identifier"
    #[mkArg "name" (.cat Str)]

  mkOp q`SolidityLean.node "Literal"
    #[mkArg "value" (.cat Str),
      mkArg "kind" (.cat Str),
      mkArg "subdenomination" (.cat Str)]

  mkOp q`SolidityLean.node "MemberAccess"
    #[mkArg "expression" (.cat Node),
      mkArg "memberName" (.cat Str)]

  mkOp q`SolidityLean.node "IndexAccess"
    #[mkArg "baseExpression" (.cat Node),
      mkArg "indexExpression" (.cat OptNode)]

  mkOp q`SolidityLean.node "IndexRangeAccess"
    #[mkArg "baseExpression" (.cat Node),
      mkArg "startExpression" (.cat OptNode),
      mkArg "endExpression" (.cat OptNode)]

  mkOp q`SolidityLean.node "InlineArrayExpression"
    #[mkArg "components" (.cat (Seq Node))]

  -- Ternary / tuple expressions
  mkOp q`SolidityLean.node "Conditional"
    #[mkArg "condition" (.cat Node),
      mkArg "trueExpression" (.cat Node),
      mkArg "falseExpression" (.cat Node)]

  mkOp q`SolidityLean.node "TupleExpression"
    #[mkArg "components" (.cat (Seq Node))]

  -- Type conversion expressions
  mkOp q`SolidityLean.node "ElementaryTypeNameExpression"
    #[mkArg "typeName" (.cat Str)]

  -- Events and errors
  mkOp q`SolidityLean.node "EventDefinition"
    #[mkArg "name" (.cat Str),
      mkArg "parameters" (.cat Node),
      mkArg "anonymous" (.cat Str)]

  mkOp q`SolidityLean.node "ErrorDefinition"
    #[mkArg "name" (.cat Str),
      mkArg "parameters" (.cat Node)]

  mkOp q`SolidityLean.node "EmitStatement"
    #[mkArg "eventCall" (.cat Node)]

  mkOp q`SolidityLean.node "RevertStatement"
    #[mkArg "errorCall" (.cat Node)]

  -- Structs
  mkOp q`SolidityLean.node "StructDefinition"
    #[mkArg "name" (.cat Str),
      mkArg "members" (.cat (Seq Node))]

  -- Enums
  mkOp q`SolidityLean.node "EnumDefinition"
    #[mkArg "name" (.cat Str),
      mkArg "members" (.cat (Seq Node))]

  mkOp q`SolidityLean.node "EnumValue"
    #[mkArg "name" (.cat Str)]

  -- Type names
  mkOp q`SolidityLean.type_name "ElementaryTypeName"
    #[mkArg "name" (.cat Str)]

  mkOp q`SolidityLean.type_name "UserDefinedTypeName"
    #[mkArg "name" (.cat Str)]

  mkOp q`SolidityLean.type_name "MappingType"
    #[mkArg "keyType" (.cat TypeName),
      mkArg "valueType" (.cat TypeName)]

  mkOp q`SolidityLean.type_name "ArrayTypeName"
    #[mkArg "baseType" (.cat TypeName)]

end Strata.Solidity
end
