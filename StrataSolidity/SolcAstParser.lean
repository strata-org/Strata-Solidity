/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/
module

public import StrataSolidity.SolcRunner
public import StrataSolidity.SolidityDialect

/-!
# Solc JSON AST → typed Lean Solidity ADT

Group B (front-end-in-Lean) of `.kiro/specs/pipeline-language-rationalization/`.
This file walks the JSON AST produced by `solc --standard-json` and constructs
a typed `Solidity.node SourceRange` value, replacing the Python `solast.py`
JSON-AST-to-Ion path on the default verification path.

## Status: SCAFFOLD

The skeleton is in place: error types, source-range parsing, the dispatch
shell on `nodeType`, and TODO stubs for each of the ~30 AST node kinds.
The full per-node translation lives in subsequent commits on this branch.

## Counterpart in Python

Mirrors `Tools/Solidity/src/solast.py:Converter.convert_node` and the
per-node `convert_*` methods. The Lean version produces typed AST nodes
directly (no DDM/Ion intermediate).

## Why typed instead of going through Ion

Ion is a binary serialization format we don't need. The JSON AST already
carries every field we'd serialize; Lean's type system can validate the
shape at parse time. Skipping Ion removes a serialization round-trip and
avoids a class of "Ion encoder/decoder disagreements" bugs.

## Migration plan

1. **(this PR)** Land the scaffold + dispatch shell.
2. Fill in `convert*` for the 30+ node kinds. Group by area: top-level,
   modifiers, functions, statements, expressions, structs/enums, type names.
3. Add a sibling test in `StrataSolidityTest/Solidity/` that runs solc
   directly on the smoke-test fixtures and asserts the resulting Lean ADT
   matches the existing Ion-derived ADT for those fixtures (parity gate).
4. Once parity holds, switch `StrataSolidityMain.lean` to dispatch on
   `.sol` inputs through this path. Keep the `.solidity.st.ion` path as
   a fallback for now (bench scripts, CI golden tests).
5. After a parallel-run window, drop the Ion path entirely (REQ-MIGR-002)
   and `solast.py`'s sole remaining purpose (Ion serialization) goes away.
-/

public section

open Lean (Json)
open Strata (SourceRange)

namespace Strata.Solidity.SolcAst

/-- Errors that can come out of mapping a solc JSON AST to a Lean ADT. -/
inductive ConvertError where
  /-- A required field was missing on a node. -/
  | missingField (nodeType : String) (field : String)
  /-- A field was present but had the wrong JSON shape. -/
  | wrongType (nodeType : String) (field : String) (got : String)
  /-- Encountered a `nodeType` we don't have a translation for. -/
  | unknownNodeType (nodeType : String)
  /-- Unimplemented: a recognized nodeType whose translator is still a stub. -/
  | unimplemented (nodeType : String)
  /-- A node lacked a `nodeType` field altogether. -/
  | missingNodeType
  deriving Repr

instance : ToString ConvertError where
  toString
    | .missingField nt f      => s!"node {nt}: missing field '{f}'"
    | .wrongType nt f got     => s!"node {nt}: field '{f}' has wrong shape: {got}"
    | .unknownNodeType nt     => s!"unknown nodeType: {nt}"
    | .unimplemented nt       => s!"nodeType not yet implemented in Group B scaffold: {nt}"
    | .missingNodeType        => s!"AST node missing 'nodeType' field"

/-- Result of a translation step. -/
abbrev ConvertM (α : Type) := Except ConvertError α

/-! ## Field accessors

A small set of helpers that pull typed values out of `Lean.Json` with
pointer-precise error messages. -/

private def getStr (nodeType : String) (j : Json) (field : String) : ConvertM String := do
  match j.getObjVal? field with
  | .ok (Json.str s) => return s
  | .ok other        => throw (.wrongType nodeType field s!"expected string, got {other}")
  | .error _         => throw (.missingField nodeType field)

private def getOptStr (j : Json) (field : String) : Option String := do
  match (j.getObjVal? field).toOption with
  | some (Json.str s) => some s
  | _                 => none

private def getArr (nodeType : String) (j : Json) (field : String) : ConvertM (Array Json) := do
  match j.getObjVal? field with
  | .ok (Json.arr a) => return a
  | .ok other        => throw (.wrongType nodeType field s!"expected array, got {other}")
  | .error _         => throw (.missingField nodeType field)

private def getNodeType (j : Json) : ConvertM String := do
  match (j.getObjVal? "nodeType").toOption with
  | some (Json.str s) => return s
  | _                 => throw .missingNodeType

/-- Parse the `src` field (`offset:length:fileIndex`) into a Lean
    `SourceRange`. Returns `default` if missing or malformed; the
    pipeline tolerates absent source positions for synthetic nodes. -/
def parseSrc (j : Json) : SourceRange := Id.run do
  match (j.getObjVal? "src").toOption with
  | some (Json.str s) =>
    match s.splitOn ":" with
    | offset :: length :: _ =>
      match offset.toNat?, length.toNat? with
      | some o, some l =>
        return { start := ⟨o⟩, stop := ⟨o + l⟩ }
      | _, _ => return default
    | _ => return default
  | _ => return default

/-! ## Top-level dispatch

The convert function walks the JSON AST recursively. Each branch
translates one `nodeType` to its Lean ADT counterpart.

Two dispatch families, mirroring the two syntax categories in the dialect:

  * `convertNode`     → `Strata.Solidity.node SourceRange`
  * `convertTypeName` → `Strata.Solidity.type_name SourceRange`

The split matches `Tools/Solidity/src/solast.py` (`convert_node` /
`convert_type_name`). Each subsequent B2.* PR fills in more arms; this
PR (B2.1) implements the three "leaf" nodes (`Identifier`, `Literal`,
`ElementaryTypeName`) — the ones with no recursive children. -/

open Strata.Solidity (node type_name)

/-- Wrap a `String` field at this node's source range. Mirrors
    `solast.py:_str` (None → empty string). -/
private def annStr (sr : SourceRange) (s : String) : Strata.Ann String SourceRange :=
  ⟨sr, s⟩

/-- Read an optional string field, defaulting to `""` if missing or wrong
    JSON shape. Matches Python's `_str(node.get(field, ""))` idiom. -/
private def getStrOr (j : Json) (field : String) (default : String := "") : String :=
  match (j.getObjVal? field).toOption with
  | some (Json.str s) => s
  | _                 => default

mutual

/-- Translate a top-level `SourceUnit` JSON node to a list of `Solidity.node`s.
    The `Command` arm of the dialect produces a `Solidity.Command`; that
    higher-level wrapping is left for the per-node implementations to land. -/
partial def convertSourceUnit (j : Json) : ConvertM Unit := do
  let nt ← getNodeType j
  if nt != "SourceUnit" then throw (.wrongType "SourceUnit" "nodeType" nt)
  let _nodes ← getArr "SourceUnit" j "nodes"
  -- TODO(group-b): walk nodes and build typed Solidity.node values.
  return ()

/-- Dispatch on `nodeType` to the appropriate per-node translator.
    Returns a typed `node SourceRange` value. -/
partial def convertNode (j : Json) : ConvertM (node SourceRange) := do
  let nt ← getNodeType j
  let sr := parseSrc j
  match nt with
  | "Identifier" =>
    -- solc: { nodeType: "Identifier", name: <string>, src: ..., ... }
    return node.Identifier sr (annStr sr (getStrOr j "name"))

  | "Literal" =>
    -- solc: { nodeType: "Literal", value: <string>, kind: "number"|"string"|"bool"|"hexString"|...,
    --         subdenomination: "ether"|"days"|... (optional), src: ... }
    -- Python defaults: value → "", kind → "number", subdenomination → "".
    let val  := getStrOr j "value" ""
    let kind := getStrOr j "kind" "number"
    let sub  := getStrOr j "subdenomination" ""
    return node.Literal sr (annStr sr val) (annStr sr kind) (annStr sr sub)

  | "PragmaDirective"
  | "ContractDefinition"
  | "ModifierDefinition" | "ModifierInvocation"
  | "FunctionDefinition" | "ParameterList" | "VariableDeclaration"
  | "Block" | "UncheckedBlock" | "ExpressionStatement"
  | "Return" | "IfStatement" | "WhileStatement" | "ForStatement"
  | "VariableDeclarationStatement"
  | "Assignment" | "BinaryOperation" | "UnaryOperation" | "FunctionCall"
  | "MemberAccess" | "IndexAccess"
  | "Conditional" | "TupleExpression" | "ElementaryTypeNameExpression"
  | "StructDefinition" | "EnumDefinition" | "EnumValue" =>
    throw (.unimplemented nt)
  | other => throw (.unknownNodeType other)

/-- Dispatch on `nodeType` for type-name positions. -/
partial def convertTypeName (j : Json) : ConvertM (type_name SourceRange) := do
  let nt ← getNodeType j
  let sr := parseSrc j
  match nt with
  | "ElementaryTypeName" =>
    -- solc: { nodeType: "ElementaryTypeName", name: <"uint256"|"bool"|...>,
    --         stateMutability: "payable"|"nonpayable" (optional, address only), src: ... }
    -- Python default: stateMutability → "".
    return type_name.ElementaryTypeName sr (annStr sr (getStrOr j "name"))
      (annStr sr (getStrOr j "stateMutability" ""))

  | "UserDefinedTypeName" | "MappingType" | "ArrayTypeName" =>
    throw (.unimplemented nt)
  | other => throw (.unknownNodeType other)

end

/-! ## Public entry point -/

/-- Run solc on `solPath`, then walk the resulting JSON AST. Returns
    `Unit` until per-node translators are filled in; subsequent PRs
    will change this to `IO (Except _ (Solidity.Command SourceRange))`. -/
def parseFile (solPath : System.FilePath) : IO (Except String Unit) := do
  match ← Strata.Solidity.Solc.parseFile solPath with
  | .error e => return .error (toString e)
  | .ok astJson =>
    match convertSourceUnit astJson with
    | .ok _ => return .ok ()
    | .error e => return .error (toString e)

end Strata.Solidity.SolcAst
end
