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
open StrataDDM (SourceRange)

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
private def annStr (sr : SourceRange) (s : String) : StrataDDM.Ann String SourceRange :=
  ⟨sr, s⟩

/-- Wrap an `Array (node SourceRange)` at this node's source range — the
    shape every "sequence of children" field requires. -/
private def annNodes (sr : SourceRange) (xs : Array (node SourceRange)) :
    StrataDDM.Ann (Array (node SourceRange)) SourceRange :=
  ⟨sr, xs⟩

/-- Wrap an `Array (Ann String SourceRange)` at this node's source range —
    the shape `FunctionCall.names` and similar use. -/
private def annStrs (sr : SourceRange) (xs : Array (StrataDDM.Ann String SourceRange)) :
    StrataDDM.Ann (Array (StrataDDM.Ann String SourceRange)) SourceRange :=
  ⟨sr, xs⟩

/-- Read an optional string field, defaulting to `""` if missing or wrong
    JSON shape. Matches Python's `_str(node.get(field, ""))` idiom. -/
private def getStrOr (j : Json) (field : String) (default : String := "") : String :=
  match (j.getObjVal? field).toOption with
  | some (Json.str s) => s
  | _                 => default

/-- Read a boolean field as a string ("true"/"false"), defaulting per arg.
    Mirrors `solast.py:_bool_str`. -/
private def getBoolStr (j : Json) (field : String) (default : Bool := true) : String :=
  match (j.getObjVal? field).toOption with
  | some (Json.bool b) => if b then "true" else "false"
  | _                  => if default then "true" else "false"

/-- Read a string-array field, returning an empty array when missing.
    Mirrors `solast.py:_seq_strings(node.get(field))`. -/
private def getStrArr (j : Json) (field : String) : Array String :=
  match (j.getObjVal? field).toOption with
  | some (Json.arr a) =>
    a.filterMap (fun
      | Json.str s => some s
      | _          => none)
  | _ => #[]

/-- Extract NatSpec documentation text. Mirrors `solast.py:_doc_text` —
    handles both old (string) and new (object with `text` field) formats. -/
private def getDocText (j : Json) : String :=
  match (j.getObjVal? "documentation").toOption with
  | some (Json.str s) => s
  | some (Json.obj _) =>
    match j.getObjVal? "documentation" with
    | .ok doc => getStrOr doc "text"
    | _ => ""
  | _ => ""

/-- NatSpec documentation text, annotated with the source range of the
    comment itself (solc's `StructuredDocumentation.src`) so that individual
    annotation lines can be located; falls back to the declaration's range
    `sr` for the old string-valued `documentation` format. -/
private def getDocAnn (sr : SourceRange) (j : Json) : StrataDDM.Ann String SourceRange :=
  let docSr := match j.getObjVal? "documentation" with
    | .ok doc@(Json.obj _) =>
      let r := parseSrc doc
      if r.isNone then sr else r
    | _ => sr
  ⟨docSr, getDocText j⟩

/-- Extract base-contract names from a `ContractDefinition.baseContracts`
    array. Each entry has shape `{baseName: {name: <string>, ...}, ...}`.
    Mirrors the inline list-comp in `solast.py:ContractDefinition`. -/
private def getBaseContractNames (j : Json) : Array String :=
  match (j.getObjVal? "baseContracts").toOption with
  | some (Json.arr a) =>
    a.filterMap (fun bc =>
      match bc.getObjVal? "baseName" with
      | .ok bn =>
        match (bn.getObjVal? "name").toOption with
        | some (Json.str s) => some s
        | _                 => none
      | .error _ => none)
  | _ => #[]

/-- Node types whose presence in a sequence is structurally noise for
    verification. Mirrors `solast.py:_SKIP_NODE_TYPES` — after Phase 2
    (events/errors, imports, using-for became first-class dialect ops)
    only NatSpec documentation nodes remain skippable. -/
private def skipNodeTypes : List String :=
  ["StructuredDocumentation"]

mutual

/-- Helper: read field `f` and recursively translate it as a `node`.
    Returns a typed `missingField` error if the field is absent. -/
partial def convertChild (parentNt : String) (f : String) (j : Json) :
    ConvertM (node SourceRange) := do
  match j.getObjVal? f with
  | .ok child => convertNode child
  | .error _  => throw (.missingField parentNt f)

/-- Helper: read optional field `f` and translate it as `opt_node`.
    Missing field, `null`, or wrong shape → `missing_node`. -/
partial def convertOptChild (sr : SourceRange) (j : Json) (f : String) :
    ConvertM (Strata.Solidity.opt_node SourceRange) := do
  match j.getObjVal? f with
  | .ok Json.null => return Strata.Solidity.opt_node.missing_node sr
  | .ok child =>
    let n ← convertNode child
    return Strata.Solidity.opt_node.some_node sr n
  | .error _  => return Strata.Solidity.opt_node.missing_node sr

/-- Helper: read field `f` as a JSON array and convert each element via
    `convertNode`. Missing field is treated as an empty array (matches
    `solast.py:_seq_nodes(node.get(field, []))`). -/
partial def convertSeqChildren (parentNt : String) (f : String) (j : Json) :
    ConvertM (Array (node SourceRange)) := do
  match j.getObjVal? f with
  | .ok (Json.arr a) => a.mapM convertNode
  | .ok Json.null    => pure #[]
  | .error _         => pure #[]
  | .ok other        => throw (.wrongType parentNt f s!"expected array, got {other}")

/-- Helper: like `convertSeqChildren` but for tuple-destructuring positions
    where elements may be `null`. Matches `solast.py:_seq_opt_nodes`. -/
partial def convertOptSeqChildren (sr : SourceRange) (parentNt : String) (f : String) (j : Json) :
    ConvertM (Array (Strata.Solidity.opt_node SourceRange)) := do
  match j.getObjVal? f with
  | .ok (Json.arr a) =>
    a.mapM (fun
      | Json.null => pure (Strata.Solidity.opt_node.missing_node sr)
      | child => do
        let n ← convertNode child
        pure (Strata.Solidity.opt_node.some_node sr n))
  | .ok Json.null => pure #[]
  | .error _      => pure #[]
  | .ok other     => throw (.wrongType parentNt f s!"expected array, got {other}")

/-- Helper: like `convertSeqChildren` but skips elements whose `nodeType`
    is in `skipNodeTypes` (NatSpec, events, emits, imports — noise for
    verification). Mirrors `solast.py:_seq_nodes`'s skip logic. -/
partial def convertSeqChildrenSkipping (parentNt : String) (f : String) (j : Json) :
    ConvertM (Array (node SourceRange)) := do
  match j.getObjVal? f with
  | .ok (Json.arr a) =>
    let kept := a.filter (fun child =>
      match (child.getObjVal? "nodeType").toOption with
      | some (Json.str nt) => !(skipNodeTypes.contains nt)
      | _                  => true)
    kept.mapM convertNode
  | .ok Json.null => pure #[]
  | .error _      => pure #[]
  | .ok other     => throw (.wrongType parentNt f s!"expected array, got {other}")

/-- Helper: read a type-name field as `opt_type_name`. Missing or null →
    `missing_type_name sr`; present → `some_type_name sr <converted>`.
    Mirrors `solast.py:_opt_type_name`. -/
partial def convertOptTypeName (sr : SourceRange) (j : Json) (f : String) :
    ConvertM (Strata.Solidity.opt_type_name SourceRange) := do
  match j.getObjVal? f with
  | .ok Json.null => return Strata.Solidity.opt_type_name.missing_type_name sr
  | .ok child =>
    let tn ← convertTypeName child
    return Strata.Solidity.opt_type_name.some_type_name sr tn
  | .error _ => return Strata.Solidity.opt_type_name.missing_type_name sr

/-- Translate a top-level `SourceUnit` JSON node to a typed
    `Solidity.Command` — the same shape `ReadSolidity.readSolidityStrata`
    produces from an Ion file, so `solidityToLaurel` can consume either
    frontend interchangeably. Skips `skipNodeTypes` children (mirrors
    `solast.py:convert_source_unit` via `_seq_nodes`). -/
partial def convertSourceUnit (j : Json) : ConvertM (Strata.Solidity.Command SourceRange) := do
  let nt ← getNodeType j
  if nt != "SourceUnit" then throw (.wrongType "SourceUnit" "nodeType" nt)
  let sr := parseSrc j
  let nodes ← convertSeqChildrenSkipping "SourceUnit" "nodes" j
  return .SourceUnit sr (annNodes sr nodes)

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

  | "Assignment" =>
    -- solc: { nodeType: "Assignment", leftHandSide, rightHandSide, operator: "="|"+="|..., ... }
    let lhs ← convertChild "Assignment" "leftHandSide" j
    let rhs ← convertChild "Assignment" "rightHandSide" j
    let op  := getStrOr j "operator" "="
    return node.Assignment sr lhs rhs (annStr sr op)

  | "BinaryOperation" =>
    -- solc: { nodeType: "BinaryOperation", leftExpression, rightExpression, operator, ... }
    let lhs ← convertChild "BinaryOperation" "leftExpression" j
    let rhs ← convertChild "BinaryOperation" "rightExpression" j
    let op  := getStrOr j "operator"
    return node.BinaryOperation sr lhs rhs (annStr sr op)

  | "UnaryOperation" =>
    -- solc: { nodeType: "UnaryOperation", subExpression, operator, prefix: true|false, ... }
    -- prefix encodes whether the operator comes before (--x) or after (x--).
    let sub ← convertChild "UnaryOperation" "subExpression" j
    let op  := getStrOr j "operator"
    let pre := getBoolStr j "prefix" true
    return node.UnaryOperation sr sub (annStr sr op) (annStr sr pre)

  | "FunctionCallOptions" =>
    -- e.g. addr.call{value: amount}("") — strip the options modifier
    -- and recurse on the wrapped expression. Matches solast.py.
    convertChild "FunctionCallOptions" "expression" j

  | "FunctionCall" =>
    -- solc: { nodeType: "FunctionCall", expression, arguments: [...], kind: "functionCall"|...,
    --        names: [...] (for named-arg calls), ... }
    let callee ← convertChild "FunctionCall" "expression" j
    let argsJ  := (j.getObjVal? "arguments").toOption.getD (Json.arr #[])
    let argArr ← match argsJ with
      | Json.arr a => a.mapM convertNode
      | _ => pure #[]
    let kind   := getStrOr j "kind" "functionCall"
    let namesJ := (j.getObjVal? "names").toOption.getD Json.null
    let names  := match namesJ with
      | Json.arr a => a.filterMap (fun
          | Json.str s => some (annStr sr s)
          | _ => none)
      | _ => #[]
    return node.FunctionCall sr callee (annNodes sr argArr) (annStr sr kind) (annStrs sr names)

  | "MemberAccess" =>
    -- solc: { nodeType: "MemberAccess", expression, memberName, ... }
    let inner ← convertChild "MemberAccess" "expression" j
    let mem   := getStrOr j "memberName"
    return node.MemberAccess sr inner (annStr sr mem)

  | "IndexAccess" =>
    -- solc: { nodeType: "IndexAccess", baseExpression, indexExpression?: optional, ... }
    -- Solidity allows arr[] in some abstract type contexts; we represent
    -- the missing index as opt_node.missing_node.
    let base ← convertChild "IndexAccess" "baseExpression" j
    let idx ← convertOptChild sr j "indexExpression"
    return node.IndexAccess sr base idx

  | "Conditional" =>
    -- solc: { nodeType: "Conditional", condition, trueExpression, falseExpression, ... }
    let c ← convertChild "Conditional" "condition" j
    let t ← convertChild "Conditional" "trueExpression" j
    let f ← convertChild "Conditional" "falseExpression" j
    return node.Conditional sr c t f

  | "TupleExpression" =>
    -- solc: { nodeType: "TupleExpression", components: [<node>|null, ...], ... }
    -- Trailing `null` slots (e.g. `(bool ok, )`) are dropped per solast.py.
    let compsJ := (j.getObjVal? "components").toOption.getD (Json.arr #[])
    let comps ← match compsJ with
      | Json.arr a =>
        a.filterMap (fun
          | Json.null => none
          | other     => some other) |>.mapM convertNode
      | _ => pure #[]
    return node.TupleExpression sr (annNodes sr comps)

  | "ElementaryTypeNameExpression" =>
    -- solc: { nodeType: "ElementaryTypeNameExpression", typeName: { name: <string> } | <string>, ... }
    -- Used for type-conversion expressions like `address(0)`. Python pulls
    -- `typeName.name` if `typeName` is an object, otherwise stringifies.
    let typeStr := match (j.getObjVal? "typeName").toOption with
      | some (Json.obj _) =>
        match j.getObjVal? "typeName" with
        | .ok tn => getStrOr tn "name"
        | _ => ""
      | some (Json.str s) => s
      | _ => ""
    return node.ElementaryTypeNameExpression sr (annStr sr typeStr)

  | "Block" =>
    -- solc: { nodeType: "Block", statements: [<node>, ...], ... }
    let stmts ← convertSeqChildren "Block" "statements" j
    return node.Block sr (annNodes sr stmts)

  | "UncheckedBlock" =>
    -- solc: { nodeType: "UncheckedBlock", statements: [<node>, ...], ... }
    -- Verification semantics same as Block; the "unchecked" wraps arithmetic
    -- so 0.8.x overflow checks are skipped — modeled as standard arithmetic
    -- by downstream translators, so we don't need to mark it specially here.
    let stmts ← convertSeqChildren "UncheckedBlock" "statements" j
    return node.UncheckedBlock sr (annNodes sr stmts)

  | "ExpressionStatement" =>
    -- solc: { nodeType: "ExpressionStatement", expression: <node>, ... }
    let e ← convertChild "ExpressionStatement" "expression" j
    return node.ExpressionStatement sr e

  | "Return" =>
    -- solc: { nodeType: "Return", expression?: <node | null>, ... }
    -- A bare `return;` has no expression.
    let v ← convertOptChild sr j "expression"
    return node.Return sr v

  | "IfStatement" =>
    -- solc: { nodeType: "IfStatement", condition, trueBody, falseBody?: optional, ... }
    let c ← convertChild "IfStatement" "condition" j
    let t ← convertChild "IfStatement" "trueBody" j
    let f ← convertOptChild sr j "falseBody"
    return node.IfStatement sr c t f

  | "WhileStatement" =>
    -- solc: { nodeType: "WhileStatement", condition, body, ... }
    let c ← convertChild "WhileStatement" "condition" j
    let b ← convertChild "WhileStatement" "body" j
    return node.WhileStatement sr c b

  | "ForStatement" =>
    -- solc: { nodeType: "ForStatement", initializationExpression?, condition?, loopExpression?, body, ... }
    -- `for (;;) {}` has all three init/cond/loop optional.
    let init ← convertOptChild sr j "initializationExpression"
    let cond ← convertOptChild sr j "condition"
    let loop ← convertOptChild sr j "loopExpression"
    let body ← convertChild "ForStatement" "body" j
    return node.ForStatement sr init cond loop body

  | "VariableDeclarationStatement" =>
    -- solc: { nodeType: "VariableDeclarationStatement", declarations: [<node>|null, ...], initialValue?, ... }
    -- Tuple destructuring: `(uint a, , bool c) = f()` produces 3 declarations
    -- with `null` in unwanted slots.
    let decls ← convertOptSeqChildren sr "VariableDeclarationStatement" "declarations" j
    let init ← convertOptChild sr j "initialValue"
    return node.VariableDeclarationStatement sr (⟨sr, decls⟩) init

  | "PlaceholderStatement" =>
    -- The `_;` in a modifier body. Not a first-class dialect op; mirror
    -- solast.py and lower it to an ExpressionStatement wrapping a string
    -- Literal "_" — downstream translators recognize this marker.
    return node.ExpressionStatement sr
      (node.Literal sr (annStr sr "_") (annStr sr "string") (annStr sr ""))

  | "PragmaDirective" =>
    -- solc: { nodeType: "PragmaDirective", literals: [<string>, ...], src: ... }
    -- E.g. `pragma solidity ^0.8.0;` → literals = ["solidity", "^", "0.8", ".0"]
    let lits := getStrArr j "literals"
    return node.PragmaDirective sr (annStrs sr (lits.map (annStr sr)))

  | "ContractDefinition" =>
    -- solc: { nodeType: "ContractDefinition", name, contractKind: "contract"|"interface"|"library",
    --        nodes: [<node>, ...] (members), baseContracts: [{baseName: {name: <string>}, ...}],
    --        documentation?, src: ... }
    let name        := getStrOr j "name"
    let kind        := getStrOr j "contractKind" "contract"
    let abstract?   := getBoolStr j "abstract" false
    let members     ← convertSeqChildrenSkipping "ContractDefinition" "nodes" j
    let doc         := getDocAnn sr j
    let baseStrs    := getBaseContractNames j
    return node.ContractDefinition sr (annStr sr name) (annStr sr kind)
      (annStr sr abstract?) (annNodes sr members) doc
      (annStrs sr (baseStrs.map (annStr sr)))

  | "ModifierDefinition" =>
    -- solc: { nodeType: "ModifierDefinition", name, parameters: <ParameterList>, body?, src: ... }
    let name   := getStrOr j "name"
    let params ← convertChild "ModifierDefinition" "parameters" j
    let body   ← convertOptChild sr j "body"
    return node.ModifierDefinition sr (annStr sr name) params body

  | "ModifierInvocation" =>
    -- solc: { nodeType: "ModifierInvocation",
    --        modifierName: { name: <string> } | <string>,
    --        arguments?: [<node>, ...], src: ... }
    let modName := match (j.getObjVal? "modifierName").toOption with
      | some (Json.obj _) =>
        match j.getObjVal? "modifierName" with
        | .ok mn => getStrOr mn "name"
        | _ => ""
      | some (Json.str s) => s
      | _ => ""
    let args ← convertSeqChildrenSkipping "ModifierInvocation" "arguments" j
    return node.ModifierInvocation sr (annStr sr modName) (annNodes sr args)

  | "FunctionDefinition" =>
    -- solc: { nodeType: "FunctionDefinition", name, kind: "function"|"constructor"|...,
    --        stateMutability: "pure"|"view"|"nonpayable"|"payable",
    --        visibility: "public"|"internal"|"external"|"private",
    --        parameters: <ParameterList>, returnParameters: <ParameterList>,
    --        body?, modifiers: [<ModifierInvocation>, ...], documentation?, src: ... }
    let name          := getStrOr j "name"
    let kind          := getStrOr j "kind" "function"
    let mut'          := getStrOr j "stateMutability"
    let vis           := getStrOr j "visibility"
    let virtual?      := getBoolStr j "virtual" false
    let params       ← convertChild "FunctionDefinition" "parameters" j
    let returnParams ← convertChild "FunctionDefinition" "returnParameters" j
    let body         ← convertOptChild sr j "body"
    let doc           := getDocAnn sr j
    let modifiers    ← convertSeqChildrenSkipping "FunctionDefinition" "modifiers" j
    return node.FunctionDefinition sr (annStr sr name) (annStr sr kind)
      (annStr sr mut') (annStr sr vis) (annStr sr virtual?)
      params returnParams body
      doc (annNodes sr modifiers)

  | "ParameterList" =>
    -- solc: { nodeType: "ParameterList", parameters: [<VariableDeclaration>, ...], src: ... }
    let params ← convertSeqChildrenSkipping "ParameterList" "parameters" j
    return node.ParameterList sr (annNodes sr params)

  | "VariableDeclaration" =>
    -- solc: { nodeType: "VariableDeclaration", name, typeName?: <type-name>,
    --        stateVariable: bool, constant: bool,
    --        storageLocation: "default"|"storage"|"memory"|"calldata",
    --        value?: <expr>, documentation?, src: ... }
    let name      := getStrOr j "name"
    let typeName ← convertOptTypeName sr j "typeName"
    let stateVar  := getBoolStr j "stateVariable" false
    let const?    := getBoolStr j "constant"      false
    let mut'      := getStrOr   j "mutability"
    let vis       := getStrOr   j "visibility"
    let indexed?  := getBoolStr j "indexed" false
    let storLoc   := getStrOr   j "storageLocation"
    let value    ← convertOptChild sr j "value"
    let doc       := getDocAnn sr j
    return node.VariableDeclaration sr (annStr sr name) typeName
      (annStr sr stateVar) (annStr sr const?)
      (annStr sr mut') (annStr sr vis) (annStr sr indexed?)
      (annStr sr storLoc) value doc

  | "StructDefinition" =>
    -- solc: { nodeType: "StructDefinition", name, members: [<VariableDeclaration>, ...], src: ... }
    let name    := getStrOr j "name"
    let members ← convertSeqChildrenSkipping "StructDefinition" "members" j
    return node.StructDefinition sr (annStr sr name) (annNodes sr members)

  | "EnumDefinition" =>
    -- solc: { nodeType: "EnumDefinition", name, members: [<EnumValue>, ...], src: ... }
    let name    := getStrOr j "name"
    let members ← convertSeqChildrenSkipping "EnumDefinition" "members" j
    return node.EnumDefinition sr (annStr sr name) (annNodes sr members)

  | "EnumValue" =>
    -- solc: { nodeType: "EnumValue", name, src: ... }
    let name := getStrOr j "name"
    return node.EnumValue sr (annStr sr name)

  | "ImportDirective" =>
    -- solc: { nodeType: "ImportDirective", file, absolutePath, unitAlias,
    --        symbolAliases: [{foreign: {name}, local?}, ...], src: ... }
    -- Encode symbolAliases as "foreign:local" strings (mirrors solast.py).
    let aliases : Array String := match (j.getObjVal? "symbolAliases").toOption with
      | some (Json.arr sas) =>
        sas.map fun sa =>
          let foreign := match (sa.getObjVal? "foreign").toOption with
            | some f => getStrOr f "name"
            | none   => ""
          let local_ := getStrOr sa "local"
          if local_.isEmpty then foreign else s!"{foreign}:{local_}"
      | _ => #[]
    return node.ImportDirective sr
      (annStr sr (getStrOr j "file"))
      (annStr sr (getStrOr j "absolutePath"))
      (annStr sr (getStrOr j "unitAlias"))
      (annStrs sr (aliases.map (annStr sr)))

  | "UserDefinedValueTypeDefinition" =>
    -- solc: { nodeType: "UserDefinedValueTypeDefinition", name, underlyingType, src: ... }
    let name := getStrOr j "name"
    match j.getObjVal? "underlyingType" with
    | .ok tyJ =>
      let ty ← convertTypeName tyJ
      return node.UserDefinedValueTypeDefinition sr (annStr sr name) ty
    | .error _ => throw (.missingField "UserDefinedValueTypeDefinition" "underlyingType")

  | "DoWhileStatement" =>
    -- solc: { nodeType: "DoWhileStatement", condition, body, src: ... }
    let cond ← convertChild "DoWhileStatement" "condition" j
    let body ← convertChild "DoWhileStatement" "body" j
    return node.DoWhileStatement sr cond body

  | "Break" =>
    -- solc emits "Break"; the dialect op is BreakStatement.
    return node.BreakStatement sr

  | "Continue" =>
    -- solc emits "Continue"; the dialect op is ContinueStatement.
    return node.ContinueStatement sr

  | "TryStatement" =>
    -- solc: { nodeType: "TryStatement", externalCall,
    --        clauses: [{errorName, parameters?, block}, ...], src: ... }
    let call ← convertChild "TryStatement" "externalCall" j
    let clauses ← match (j.getObjVal? "clauses").toOption with
      | some (Json.arr cs) => cs.mapM fun c => do
          let csr := parseSrc c
          let errName := getStrOr c "errorName"
          let params ← convertOptChild csr c "parameters"
          let block ← convertChild "TryCatchClause" "block" c
          pure (node.TryCatchClause csr (annStr csr errName) params block)
      | _ => pure #[]
    return node.TryStatement sr call (annNodes sr clauses)

  | "InlineAssembly" =>
    -- solc: { nodeType: "InlineAssembly", AST: <Yul AST>, src: ... }
    -- Serialize the Yul AST as a JSON string payload; the translator uses
    -- the havoc strategy. Mirrors solast.py.
    let yulPayload := match (j.getObjVal? "AST").toOption with
      | some yul => yul.compress
      | none     => ""
    return node.InlineAssembly sr (annStr sr yulPayload)

  | "IndexRangeAccess" =>
    -- solc: { nodeType: "IndexRangeAccess", baseExpression, startExpression?, endExpression?, ... }
    let base ← convertChild "IndexRangeAccess" "baseExpression" j
    let startE ← convertOptChild sr j "startExpression"
    let endE ← convertOptChild sr j "endExpression"
    return node.IndexRangeAccess sr base startE endE

  | "InlineArrayExpression" =>
    -- solc: { nodeType: "InlineArrayExpression", components: [<expr>, ...], ... }
    let comps ← convertSeqChildrenSkipping "InlineArrayExpression" "components" j
    return node.InlineArrayExpression sr (annNodes sr comps)

  | "NewExpression" =>
    -- solc: { nodeType: "NewExpression", typeName: <type-name>, ... }
    match j.getObjVal? "typeName" with
    | .ok tyJ =>
      let ty ← convertTypeName tyJ
      return node.NewExpression sr ty
    | .error _ => throw (.missingField "NewExpression" "typeName")

  | "EventDefinition" =>
    -- solc: { nodeType: "EventDefinition", name, parameters, anonymous, src: ... }
    let name := getStrOr j "name"
    let params ← convertChild "EventDefinition" "parameters" j
    return node.EventDefinition sr (annStr sr name) params
      (annStr sr (getBoolStr j "anonymous" false))

  | "ErrorDefinition" =>
    -- solc: { nodeType: "ErrorDefinition", name, parameters, src: ... }
    let name := getStrOr j "name"
    let params ← convertChild "ErrorDefinition" "parameters" j
    return node.ErrorDefinition sr (annStr sr name) params

  | "EmitStatement" =>
    -- solc: { nodeType: "EmitStatement", eventCall, src: ... }
    let call ← convertChild "EmitStatement" "eventCall" j
    return node.EmitStatement sr call

  | "RevertStatement" =>
    -- solc: { nodeType: "RevertStatement", errorCall, src: ... }
    let call ← convertChild "RevertStatement" "errorCall" j
    return node.RevertStatement sr call

  | "UsingForDirective" =>
    -- solc: { nodeType: "UsingForDirective", libraryName: {name}?, typeName?, global?, ... }
    let libName := match (j.getObjVal? "libraryName").toOption with
      | some ln => getStrOr ln "name"
      | none    => ""
    let tyName ← convertOptTypeName sr j "typeName"
    return node.UsingForDirective sr (annStr sr libName) tyName
      (annStr sr (getBoolStr j "global" false))

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

  | "UserDefinedTypeName" =>
    -- solc: { nodeType: "UserDefinedTypeName",
    --        pathNode: { nodeType: "IdentifierPath", name: <string>, ... },
    --        src: ... }
    -- The Solidity 0.8.x AST nests the actual identifier under `pathNode`.
    -- Python's solast.py treats a missing/empty path-name as fatal; we
    -- propagate the same as a typed error.
    match j.getObjVal? "pathNode" with
    | .ok pathNode =>
      let name := getStrOr pathNode "name"
      if name.isEmpty then
        throw (.missingField "UserDefinedTypeName" "pathNode.name")
      return type_name.UserDefinedTypeName sr (annStr sr name)
    | .error _ => throw (.missingField "UserDefinedTypeName" "pathNode")

  | "Mapping" =>
    -- solc: { nodeType: "Mapping",
    --        keyType: <type-name node>,
    --        valueType: <type-name node>,
    --        keyName: <string> (optional, named mapping keys),
    --        valueName: <string> (optional),
    --        src: ... }
    -- Note solc emits "Mapping" (not "MappingType"); the dialect's op
    -- constructor is named MappingType. Python defaults key/value names
    -- to "" when absent.
    match j.getObjVal? "keyType", j.getObjVal? "valueType" with
    | .ok keyJ, .ok valJ =>
      let keyTy ← convertTypeName keyJ
      let valTy ← convertTypeName valJ
      return type_name.MappingType sr keyTy valTy
        (annStr sr (getStrOr j "keyName" "")) (annStr sr (getStrOr j "valueName" ""))
    | .error _, _ => throw (.missingField "Mapping" "keyType")
    | _, .error _ => throw (.missingField "Mapping" "valueType")

  | "ArrayTypeName" =>
    -- solc: { nodeType: "ArrayTypeName", baseType: <type-name node>, src: ... }
    -- The optional `length` field (for fixed-size arrays) is intentionally
    -- ignored — matches solast.py.
    match j.getObjVal? "baseType" with
    | .ok baseJ =>
      let baseTy ← convertTypeName baseJ
      return type_name.ArrayTypeName sr baseTy
    | .error _ => throw (.missingField "ArrayTypeName" "baseType")

  | "FunctionTypeName" =>
    -- solc: { nodeType: "FunctionTypeName", parameterTypes: <ParameterList>,
    --        returnParameterTypes: <ParameterList>, visibility, stateMutability, ... }
    let params ← convertChild "FunctionTypeName" "parameterTypes" j
    let retParams ← convertChild "FunctionTypeName" "returnParameterTypes" j
    return type_name.FunctionTypeName sr params retParams
      (annStr sr (getStrOr j "visibility"))
      (annStr sr (getStrOr j "stateMutability"))

  | other =>
    -- Fallback: wrap unknown type names as ElementaryTypeName carrying the
    -- solc typeString (mirrors solast.py's convert_type_name fallback).
    let ts := match (j.getObjVal? "typeDescriptions").toOption with
      | some td => getStrOr td "typeString" s!"unknown:{other}"
      | none    => s!"unknown:{other}"
    return type_name.ElementaryTypeName sr (annStr sr ts) (annStr sr "")

end

/-! ## Public entry point -/

/-- Solidity identifiers may start with `$` (e.g. OpenZeppelin's ERC-7201
    storage pointer `$`), but Laurel reserves a leading `$` for
    compiler-generated names. Such identifiers are renamed by replacing the
    leading `$` with `dollarPrefix`. -/
def dollarPrefix : String := "strata$dollar$"

/-- `$x` ↦ `strata$dollar$x`; other names are unchanged. -/
def mangleName (s : String) : String :=
  if s.startsWith "$" then dollarPrefix ++ (s.drop 1).toString else s

/-- Inverse of `mangleName`, for messages shown to the user. -/
def unmangleName (s : String) : String :=
  s.replace dollarPrefix "$"

/-- Apply `mangleName` to every declared or referenced name in a solc JSON
    AST (`name` and `memberName` fields). -/
partial def mangleNames : Json → Json
  | .obj kvs => Json.mkObj (kvs.toList.map fun (k, v) =>
      (k, match k, v with
        | "name", .str s | "memberName", .str s => .str (mangleName s)
        | _, v => mangleNames v))
  | .arr xs => .arr (xs.map mangleNames)
  | j => j

/-- Run solc on `solPath`, then walk the resulting JSON AST into a typed
    `Solidity.Command` — the same shape the Ion path produces, ready for
    `solidityToLaurel`. -/
def parseFile (solPath : System.FilePath)
    : IO (Except String (Strata.Solidity.Command SourceRange)) := do
  match ← Strata.Solidity.Solc.parseFile solPath with
  | .error e => return .error (toString e)
  | .ok astJson =>
    match convertSourceUnit (mangleNames astJson) with
    | .ok cmd => return .ok cmd
    | .error e => return .error (toString e)

end Strata.Solidity.SolcAst
end
