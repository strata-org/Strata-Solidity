/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

import Strata.Languages.Laurel.Laurel
import Strata.Languages.Laurel.LaurelToCoreTranslator
import Strata.Languages.Laurel.Grammar.ConcreteToAbstractTreeTranslator
import Strata.Languages.Core.Verifier
import Strata.Languages.Solidity.SolidityDialect
import Strata.Languages.Solidity.ReadSolidity
import Strata.DL.Imperative.MetaData

/-!
# Solidity AST → Laurel Translation

Translates the Solidity DDM AST (produced by solc → solast.py → Ion)
into the Laurel intermediate representation.

## Scope
- Pure/view functions with value types (uint256, int256, bool, address)
- `require(cond)` → assume, `assert(cond)` → assert
- if/else, while, for loops, return, variable declarations, assignments
- Arithmetic and comparison operators
- Contracts as CompositeType with state-variable fields + static procedures
- Struct definitions as CompositeType

## Design (Option A from design doc)
Uses `solc --ast-json` via the external Python tooling; this module
only handles the Lean-side translation from typed DDM AST to Laurel.
-/

namespace Strata.Solidity

open Laurel

/-! ## Helpers -/

def defaultMetadata : Imperative.MetaData Core.Expression := #[]

/-- Convert a SourceRange and file URI to Laurel metadata with file range info.
    Reuses the existing `SourceRange.toMetaData` from the Laurel grammar translator. -/
def sourceRangeToMd (uri : Uri) (sr : SourceRange) : Imperative.MetaData Core.Expression :=
  if sr.isNone then #[]
  else Laurel.SourceRange.toMetaData uri sr

/-- A storage reference alias: records the struct type and field info so that
    field accesses through the alias can be desugared to per-field scalar
    local variables. E.g., `sender.weight` → `Identifier "sender__weight"`. -/
structure StorageAlias where
  /-- The struct type name (e.g., "Voter"). -/
  structTypeName : String
  /-- Ordered list of (field name, field type) pairs. -/
  fields : List (String × HighType)

/-- Translation context carrying the source file URI for metadata
    and struct field orders for argument reordering. -/
structure TransCtx where
  uri : Option Uri
  /-- Map from struct name to ordered list of (field name, field type) pairs. -/
  structFields : List (String × List (String × HighType)) := []
  /-- Enclosing contract name (for constructor naming). -/
  contractName : String := ""
  /-- State-variable fields of the enclosing contract (for constructor outputs). -/
  contractFields : List Field := []
  /-- Storage reference aliases: maps alias name to its alias info.
      Field accesses `alias.field` are desugared to `Identifier "alias__field"`. -/
  storageAliases : List (String × StorageAlias) := []
  /-- Names of state variables in the enclosing contract.
      Used to translate bare identifiers to `FieldSelect self "name"`.
      Exception: mapping state vars in this list are intercepted earlier
      and translated to bare `Identifier` (they are explicit parameters). -/
  -- TODO: Use HashSet for O(1) lookup if contracts grow large.
  stateVarNames : List String := []
  /-- Names of mapping-typed state variables. These are passed as explicit
      parameters rather than going through the heap (Box has no Map variant).
      Bare identifiers for these produce `Identifier name` (the parameter).
      NOTE: Array state vars are also included here (they use TMap TInt T). -/
  mappingStateVars : List String := []
  /-- Names of array-typed state variables (subset of mappingStateVars).
      These get an additional `name_length` parameter for tracking length. -/
  arrayStateVars : List String := []
  /-- Names of memory array parameters in the current function.
      These get a paired `name_length` parameter for `.length` access. -/
  memoryArrayParams : List String := []
  /-- Names of non-pure functions in the enclosing contract.
      Internal calls to these functions need `self` threaded through. -/
  -- TODO: Use HashSet for O(1) lookup if contracts grow large.
  nonPureFunctions : List String := []
  /-- Names of in-scope local variables and function parameters.
      Checked before `stateVarNames` so that locals/params shadow state variables. -/
  -- TODO: Use HashSet for O(1) lookup if contracts grow large.
  localNames : List String := []
  -- TODO: Add a debug/trace flag that prints the generated Laurel IR for each function.
  -- This would help catch issues like uninitialized storage refs, missing $heap threading,
  -- and Block wrapper problems during development.
  /-- Contract-level invariant DDM nodes (from `_strata_invariant` in constructor).
      Stored as raw DDM nodes and re-translated per function context so that
      state variable references resolve correctly in each function. -/
  contractInvariantNodes : List (Solidity.node SourceRange) := []
  /-- Contract-level invariant expressions parsed from NatSpec `@custom:strata invariant`.
      These are pre-parsed StmtExprMd and don't need re-translation per function. -/
  contractInvariantNatspec : List StmtExprMd := []

def mkHighTypeMd (ty : HighType) : HighTypeMd :=
  { val := ty, md := defaultMetadata }

def mkStmtExprMd (expr : StmtExpr) : StmtExprMd :=
  { val := expr, md := defaultMetadata }

/-- Create a StmtExprMd with source location metadata. -/
def mkStmtExprMdAnn (ctx : TransCtx) (sr : SourceRange) (expr : StmtExpr) : StmtExprMd :=
  match ctx.uri with
  | some uri => { val := expr, md := sourceRangeToMd uri sr }
  | none => { val := expr, md := defaultMetadata }

/-! ## Translation Error -/

inductive TranslationError where
  | unsupported (msg : String)
  | typeError (msg : String)
  | internalError (msg : String)
deriving Repr

def TranslationError.toString : TranslationError → String
  | .unsupported msg => s!"Unsupported: {msg}"
  | .typeError msg => s!"Type error: {msg}"
  | .internalError msg => s!"Internal error: {msg}"

instance : ToString TranslationError where
  toString := TranslationError.toString

/-! ## Type Translation -/

/-- Solidity type info: Laurel type + whether it needs uint256 bounds. -/
structure SolType where
  highType : HighTypeMd
  /-- Original Solidity type name for bounds generation. -/
  solName : String
deriving Inhabited

/-- Translate a Solidity type name string to Laurel HighType.
    Phase 1: bool → TBool; address, uint*, bytes* → TInt (unsigned);
    int*, and all other types → TInt (default). -/
def translateTypeName (name : String) : SolType :=
  if name == "bool" then { highType := mkHighTypeMd .TBool, solName := name }
  else if name == "address" then { highType := mkHighTypeMd .TInt, solName := name }
  else { highType := mkHighTypeMd .TInt, solName := name }

/-- Translate a DDM type_name node to SolType. -/
def translateTypeNode (tn : Solidity.type_name SourceRange) : SolType :=
  match tn with
  | .ElementaryTypeName _ nameAnn => translateTypeName nameAnn.val
  | .UserDefinedTypeName _ nameAnn =>
    { highType := mkHighTypeMd (.UserDefined ⟨nameAnn.val, none⟩), solName := nameAnn.val }
  | .MappingType _ keyTn valTn =>
    let k := (translateTypeNode keyTn).highType
    let v := (translateTypeNode valTn).highType
    { highType := mkHighTypeMd (.TMap k v), solName := "mapping" }
  | .ArrayTypeName _ baseTn =>
    let elem := (translateTypeNode baseTn).highType
    -- NOTE: Design doc specifies `TMap Nat T` but Laurel's HighType has no TNat variant,
    -- so we use TInt as the key type. This means array indices can be negative in the SMT
    -- encoding; we compensate by asserting idx >= 0 at each IndexAccess site.
    { highType := mkHighTypeMd (.TMap (mkHighTypeMd .TInt) elem), solName := "array" }

/-- Is this a Solidity unsigned integer type? -/
def SolType.isUint (st : SolType) : Bool :=
  st.solName.startsWith "uint"

/-- Is this a Solidity address type? -/
def SolType.isAddress (st : SolType) : Bool :=
  st.solName == "address"

/-- Is this a Solidity bytes type (bytes1–bytes32)? -/
def SolType.isBytes (st : SolType) : Bool :=
  st.solName.startsWith "bytes"

/-- Generate the Solidity default (zero) value for a given HighType.
    Scalars get 0 or false; mappings get `const(defaultVal(valueType))`. -/
partial def defaultValueForType (ty : HighTypeMd) : StmtExprMd :=
  match ty.val with
  | .TBool => mkStmtExprMd (.LiteralBool false)
  | .TMap _ v => mkStmtExprMd (.StaticCall "const" [defaultValueForType v])
  | _ => mkStmtExprMd (.LiteralInt 0)

/-- Generate a non-negative precondition: param >= 0 -/
def mkNonNegPrecond (paramName : String) : StmtExprMd :=
  let ident := mkStmtExprMd (.Identifier paramName)
  let zero := mkStmtExprMd (.LiteralInt 0)
  mkStmtExprMd (.PrimitiveOp .Geq [ident, zero])

/-! ## Expression Translation -/

/-- Check if a VariableDeclarationStatement declares a storage reference. -/
def isStorageRefDecl (n : Solidity.node SourceRange) : Option (String × Solidity.opt_node SourceRange) :=
  match n with
  | .VariableDeclarationStatement _ declsSeq initOpt =>
    match declsSeq.val.toList with
    | [declOpt] =>
      match declOpt with
      | .some_node _ (.VariableDeclaration _ nameAnn _ _ _ storageLocAnn) =>
        if storageLocAnn.val == "storage" then some (nameAnn.val, initOpt) else none
      | _ => none
    | _ => none
  | _ => none

/-- Extract the struct type name from a storage reference VariableDeclarationStatement.
    Returns `none` if the type is not a UserDefinedTypeName. -/
def extractStorageRefTypeName (n : Solidity.node SourceRange) : Option String :=
  match n with
  | .VariableDeclarationStatement _ declsSeq _ =>
    match declsSeq.val.toList with
    | [.some_node _ (.VariableDeclaration _ _ typeNameOpt _ _ _)] =>
      match typeNameOpt with
      | .some_type_name _ (.UserDefinedTypeName _ nameAnn) => some nameAnn.val
      | _ => none
    | _ => none
  | _ => none

/-- Collect index expressions from array IndexAccess nodes in a Solidity AST node.
    Returns index nodes whose base is a known array state variable or memory array parameter.
    Only collects simple index expressions (identifiers, literals, binary ops on those)
    to avoid duplicating side-effectful expressions like function calls.
    Used to emit `assert(idx >= 0)` as preceding statements (not expression wrappers). -/
partial def collectArrayIndexNodes (ctx : TransCtx) (n : Solidity.node SourceRange)
    : List (Solidity.node SourceRange) :=
  match n with
  | .IndexAccess _ baseNode indexOpt =>
    let baseIsArray := match baseNode with
      | .Identifier _ nameAnn =>
        ctx.arrayStateVars.contains nameAnn.val || ctx.memoryArrayParams.contains nameAnn.val
      | _ => false
    let idxIsSafe := match indexOpt with
      | .some_node _ (.Identifier _ _) => true
      | .some_node _ (.Literal _ _ _) => true
      | .some_node _ (.BinaryOperation _ _ _ _) => true
      | _ => false
    let fromIdx := match indexOpt with
      | .some_node _ idx =>
        if baseIsArray && idxIsSafe then [idx]
        else collectArrayIndexNodes ctx idx
      | .missing_node _ => []
    collectArrayIndexNodes ctx baseNode ++ fromIdx
  | .BinaryOperation _ l r _ => collectArrayIndexNodes ctx l ++ collectArrayIndexNodes ctx r
  | .UnaryOperation _ operand _ _ => collectArrayIndexNodes ctx operand
  | .FunctionCall _ fnExpr argsSeq _ _ =>
    collectArrayIndexNodes ctx fnExpr ++
    ((argsSeq.val.toList.map (collectArrayIndexNodes ctx)).flatten)
  | .MemberAccess _ base _ => collectArrayIndexNodes ctx base
  | .Assignment _ lhs rhs _ => collectArrayIndexNodes ctx lhs ++ collectArrayIndexNodes ctx rhs
  | _ => []

/-- Collect array index check nodes from a statement's immediate expressions.
    Does NOT recurse into compound statements (for, while, if bodies) since
    assertions must be emitted in the correct scope. -/
partial def collectArrayIndexNodesStmt (ctx : TransCtx) (n : Solidity.node SourceRange)
    : List (Solidity.node SourceRange) :=
  match n with
  | .ExpressionStatement _ expr => collectArrayIndexNodes ctx expr
  | .VariableDeclarationStatement _ _ initOpt =>
    match initOpt with
    | .some_node _ initNode => collectArrayIndexNodes ctx initNode
    | .missing_node _ => []
  | .Return _ exprOpt =>
    match exprOpt with
    | .some_node _ expr => collectArrayIndexNodes ctx expr
    | .missing_node _ => []
  -- Do not recurse into compound statements; their bodies are handled
  -- by translateBlockStmts/translateStmt recursively.
  | _ => []

/-- Collect a chain of IndexAccess nodes from an LHS expression.
    Returns `(rootNode, [idx1, idx2, ...])` where rootNode is the innermost
    non-IndexAccess base and the indices are in outermost-to-innermost order.
    E.g., `m[k1][k2]` → `(m, [k1, k2])`.
    Returns `none` for non-IndexAccess nodes. -/
def collectIndexChain (n : Solidity.node SourceRange)
    : Option (Solidity.node SourceRange × List (Solidity.node SourceRange)) :=
  match n with
  | .IndexAccess _ baseNode (.some_node _ idx) =>
    let rec go (n : Solidity.node SourceRange) (acc : List (Solidity.node SourceRange))
        : Solidity.node SourceRange × List (Solidity.node SourceRange) :=
      match n with
      | .IndexAccess _ baseNode (.some_node _ idx) => go baseNode (idx :: acc)
      | root => (root, acc)
    some (go baseNode (idx :: []))
  | _ => none

/-- Build a nested map update expression.
    For a single index: `update(root, k, val)`
    For nested indices `[k1, k2]`: `update(root, k1, update(select(root, k1), k2, val))` -/
def buildNestedUpdate (rootExpr : StmtExprMd) (indices : List StmtExprMd) (val : StmtExprMd)
    : Except TranslationError StmtExprMd := do
  match indices with
  | [] => throw (.internalError "buildNestedUpdate: empty index list")
  | [idx] => return mkStmtExprMd (.StaticCall "update" [rootExpr, idx, val])
  | idx :: rest =>
    let inner := mkStmtExprMd (.StaticCall "select" [rootExpr, idx])
    let innerUpdate ← buildNestedUpdate inner rest val
    return mkStmtExprMd (.StaticCall "update" [rootExpr, idx, innerUpdate])

/-! ## Specification Extraction Helpers -/

/-- A parsed `@custom:strata` annotation. -/
inductive StrataAnnotation where
  | requires (expr : String)
  | ensures (expr : String)
  | invariant (expr : String)
  | modifies (vars : String)
  | loopInvariant (expr : String)

/-- Parse `@custom:strata` annotations from a NatSpec documentation string.
    Each line matching `@custom:strata <keyword> <expr>` produces an annotation. -/
def parseStrataAnnotations (doc : String) : List StrataAnnotation :=
  let lines := doc.splitOn "\n" |>.map String.trim
  lines.filterMap fun line =>
    let prefix := "@custom:strata "
    if line.startsWith prefix then
      let rest := (line.drop prefix.length).trim
      if rest.startsWith "requires " then
        some (.requires ((rest.drop "requires ".length).trim))
      else if rest.startsWith "ensures " then
        some (.ensures ((rest.drop "ensures ".length).trim))
      else if rest.startsWith "invariant " then
        some (.invariant ((rest.drop "invariant ".length).trim))
      else if rest.startsWith "modifies " then
        some (.modifies ((rest.drop "modifies ".length).trim))
      else if rest.startsWith "loop-invariant " then
        some (.loopInvariant ((rest.drop "loop-invariant ".length).trim))
      else none
    else none

/-! ## Spec Expression Parser

Recursive descent parser for `@custom:strata` annotation expressions.
Supports: identifiers, integer literals, `true`/`false`, `old(expr)`,
`msg.sender`, `msg.value`, member access (`x.y`), index access (`x[y]`),
binary operators (`==`, `!=`, `>=`, `<=`, `>`, `<`, `+`, `-`, `*`),
boolean operators (`&&`, `||`), and parentheses.
-/

namespace SpecParser

/-- Tokenize a spec expression string into a list of tokens. -/
private def tokenize (s : String) : List String :=
  let rec go (i : Nat) (acc : List String) (cur : String) (fuel : Nat) : List String :=
    if fuel == 0 then (if cur.isEmpty then acc else acc ++ [cur]).reverse
    else if i >= s.length then (if cur.isEmpty then acc else acc ++ [cur])
    else
      let c := s.get ⟨i⟩
      if c == ' ' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 1) acc' "" (fuel - 1)
      else if c == '(' || c == ')' || c == '[' || c == ']' || c == ',' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 1) (acc' ++ [c.toString]) "" (fuel - 1)
      else if c == '=' && i + 1 < s.length && s.get ⟨i+1⟩ == '=' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 2) (acc' ++ ["=="]) "" (fuel - 1)
      else if c == '!' && i + 1 < s.length && s.get ⟨i+1⟩ == '=' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 2) (acc' ++ ["!="]) "" (fuel - 1)
      else if c == '>' && i + 1 < s.length && s.get ⟨i+1⟩ == '=' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 2) (acc' ++ [">="]) "" (fuel - 1)
      else if c == '<' && i + 1 < s.length && s.get ⟨i+1⟩ == '=' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 2) (acc' ++ ["<="]) "" (fuel - 1)
      else if c == '&' && i + 1 < s.length && s.get ⟨i+1⟩ == '&' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 2) (acc' ++ ["&&"]) "" (fuel - 1)
      else if c == '|' && i + 1 < s.length && s.get ⟨i+1⟩ == '|' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 2) (acc' ++ ["||"]) "" (fuel - 1)
      else if c == '>' || c == '<' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 1) (acc' ++ [c.toString]) "" (fuel - 1)
      else if c == '+' || c == '-' || c == '*' || c == '.' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 1) (acc' ++ [c.toString]) "" (fuel - 1)
      else
        go (i + 1) acc (cur.push c) (fuel - 1)
  go 0 [] "" (s.length * 4 + 10)

private def isDigitStr (s : String) : Bool :=
  !s.isEmpty && s.toList.all Char.isDigit

/-- Parse a spec expression string into a Laurel StmtExprMd.
    Returns the parsed expression and remaining tokens. -/
private partial def parseExpr (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
  parseOr tokens

where
  parseOr (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseAnd tokens
    match rest with
    | "||" :: rest' =>
      let (rhs, rest'') ← parseOr rest'
      return (mkStmtExprMd (.PrimitiveOp .Or [lhs, rhs]), rest'')
    | _ => return (lhs, rest)

  parseAnd (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseComparison tokens
    match rest with
    | "&&" :: rest' =>
      let (rhs, rest'') ← parseAnd rest'
      return (mkStmtExprMd (.PrimitiveOp .And [lhs, rhs]), rest'')
    | _ => return (lhs, rest)

  parseComparison (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseAddSub tokens
    match rest with
    | "==" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (.PrimitiveOp .Eq [lhs, rhs]), rest'')
    | "!=" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (.PrimitiveOp .Neq [lhs, rhs]), rest'')
    | ">=" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (.PrimitiveOp .Geq [lhs, rhs]), rest'')
    | "<=" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (.PrimitiveOp .Leq [lhs, rhs]), rest'')
    | ">" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (.PrimitiveOp .Gt [lhs, rhs]), rest'')
    | "<" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (.PrimitiveOp .Lt [lhs, rhs]), rest'')
    | _ => return (lhs, rest)

  parseAddSub (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseMul tokens
    parseAddSubTail lhs rest

  parseAddSubTail (lhs : StmtExprMd) (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    match tokens with
    | "+" :: rest =>
      let (rhs, rest') ← parseMul rest
      parseAddSubTail (mkStmtExprMd (.PrimitiveOp .Add [lhs, rhs])) rest'
    | "-" :: rest =>
      let (rhs, rest') ← parseMul rest
      parseAddSubTail (mkStmtExprMd (.PrimitiveOp .Sub [lhs, rhs])) rest'
    | _ => return (lhs, tokens)

  parseMul (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parsePostfix tokens
    parseMulTail lhs rest

  parseMulTail (lhs : StmtExprMd) (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    match tokens with
    | "*" :: rest =>
      let (rhs, rest') ← parsePostfix rest
      parseMulTail (mkStmtExprMd (.PrimitiveOp .Mul [lhs, rhs])) rest'
    | _ => return (lhs, tokens)

  parsePostfix (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (base, rest) ← parseAtom tokens
    parsePostfixTail base rest

  parsePostfixTail (base : StmtExprMd) (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    match tokens with
    | "[" :: rest =>
      let (idx, rest') ← parseExpr rest
      match rest' with
      | "]" :: rest'' =>
        let sel := mkStmtExprMd (.StaticCall "select" [base, idx])
        parsePostfixTail sel rest''
      | _ => throw (.typeError "Expected ']' in index access")
    | "." :: member :: rest =>
      if member == "length" then
        -- x.length → Identifier "x_length" (for arrays)
        match base.val with
        | .Identifier name => parsePostfixTail (mkStmtExprMd (.Identifier s!"{name}_length")) rest
        | _ => throw (.typeError "length access on non-identifier")
      else
        parsePostfixTail (mkStmtExprMd (.FieldSelect base ⟨member, none⟩)) rest
    | _ => return (base, tokens)

  parseAtom (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    match tokens with
    | [] => throw (.typeError "Unexpected end of spec expression")
    | "(" :: rest =>
      let (inner, rest') ← parseExpr rest
      match rest' with
      | ")" :: rest'' => return (inner, rest'')
      | _ => throw (.typeError "Expected ')' in spec expression")
    | "true" :: rest => return (mkStmtExprMd (.LiteralBool true), rest)
    | "false" :: rest => return (mkStmtExprMd (.LiteralBool false), rest)
    | "old" :: "(" :: rest =>
      let (inner, rest') ← parseExpr rest
      match rest' with
      | ")" :: rest'' =>
        -- Mark old() expressions with a StaticCall "__old" so they can be
        -- identified and rewritten by rewriteOldMappingRefs later.
        return (mkStmtExprMd (.StaticCall "__old" [inner]), rest'')
      | _ => throw (.typeError "Expected ')' after old(")
    | "msg" :: "." :: "sender" :: rest =>
      return (mkStmtExprMd (.Identifier "msg_sender"), rest)
    | "msg" :: "." :: "value" :: rest =>
      return (mkStmtExprMd (.Identifier "msg_value"), rest)
    | tok :: rest =>
      if isDigitStr tok then
        match tok.toNat? with
        | some n => return (mkStmtExprMd (.LiteralInt n), rest)
        | none => throw (.typeError s!"Invalid integer literal: {tok}")
      else
        return (mkStmtExprMd (.Identifier tok), rest)

end SpecParser

/-- Parse a spec expression string into a Laurel StmtExprMd. -/
def parseSpecExpr (s : String) : Except TranslationError StmtExprMd := do
  let tokens := SpecParser.tokenize s
  let (expr, rest) ← SpecParser.parseExpr tokens
  if !rest.isEmpty then
    throw (.typeError s!"Unexpected tokens after spec expression: {rest}")
  return expr

/-- Process `__old` markers in a parsed spec expression.
    Replaces `StaticCall "__old" [inner]` by applying `rewriteOldMappingRefs`
    to the inner expression (rewrites mapping state vars to `_in` versions). -/
partial def processOldMarkers (mappingStateVars : List String) (arrayStateVars : List String)
    (expr : StmtExprMd) : StmtExprMd :=
  let go := processOldMarkers mappingStateVars arrayStateVars
  match expr.val with
  | .StaticCall "__old" args =>
    match args with
    | [inner] => rewriteOldMappingRefs mappingStateVars arrayStateVars (go inner)
    | _ => expr
  | .PrimitiveOp op args =>
    { expr with val := .PrimitiveOp op (args.map go) }
  | .StaticCall callee args =>
    { expr with val := .StaticCall callee (args.map go) }
  | .FieldSelect target fieldName =>
    { expr with val := .FieldSelect (go target) fieldName }
  | .IfThenElse cond thenBr elseBr =>
    { expr with val := .IfThenElse (go cond) (go thenBr) (elseBr.map go) }
  | _ => expr

/-- Check if a Solidity AST node is a call to a named function. -/
def isCallTo (name : String) (n : Solidity.node SourceRange) : Bool :=
  match n with
  | .FunctionCall _ (.Identifier _ nameAnn) _ _ _ => nameAnn.val == name
  | _ => false

/-- Check if a Solidity AST node is a _strata_loop_invariant call. -/
def isLoopInvariantCall (n : Solidity.node SourceRange) : Bool :=
  isCallTo "_strata_loop_invariant" n

/-- Extract the argument expression from a single-argument FunctionCall node. -/
def extractCallArg (n : Solidity.node SourceRange) : Option (Solidity.node SourceRange) :=
  match n with
  | .FunctionCall _ _ argsSeq _ _ =>
    match argsSeq.val.toList with
    | [arg] => some arg
    | _ => none
  | _ => none

/-- Extract _strata_pre and _strata_post calls from a Block's top-level statements.
    Returns (preConds, postConds, remainingStmts). -/
def partitionSpecStmts (stmts : List (Solidity.node SourceRange))
    : List (Solidity.node SourceRange) × List (Solidity.node SourceRange) × List (Solidity.node SourceRange) :=
  let rec go (remaining : List (Solidity.node SourceRange))
      (pres posts others : List (Solidity.node SourceRange))
      : List (Solidity.node SourceRange) × List (Solidity.node SourceRange) × List (Solidity.node SourceRange) :=
    match remaining with
    | [] => (pres.reverse, posts.reverse, others.reverse)
    | stmt :: rest =>
      match stmt with
      | .ExpressionStatement _ expr =>
        if isCallTo "_strata_pre" expr then
          go rest (expr :: pres) posts others
        else if isCallTo "_strata_post" expr then
          go rest pres (expr :: posts) others
        else if isCallTo "_strata_invariant" expr then
          go rest pres posts others
        else
          go rest pres posts (stmt :: others)
      | _ => go rest pres posts (stmt :: others)
  go stmts [] [] []

/-- Extract _strata_loop_invariant calls from the beginning of a loop body's statements.
    Returns (invariantExprs, remainingStmts). -/
def extractLoopInvariants (stmts : List (Solidity.node SourceRange))
    : List (Solidity.node SourceRange) × List (Solidity.node SourceRange) :=
  let rec go (remaining : List (Solidity.node SourceRange))
      (invs : List (Solidity.node SourceRange))
      : List (Solidity.node SourceRange) × List (Solidity.node SourceRange) :=
    match remaining with
    | [] => (invs.reverse, [])
    | stmt :: rest =>
      match stmt with
      | .ExpressionStatement _ expr =>
        if isLoopInvariantCall expr then
          go rest (expr :: invs)
        else
          (invs.reverse, remaining)
      | _ => (invs.reverse, remaining)
  go stmts []

/-- Extract _strata_invariant calls from a constructor body.
    Returns the invariant argument expressions. -/
def extractContractInvariants (bodyStmts : List (Solidity.node SourceRange))
    : List (Solidity.node SourceRange) :=
  bodyStmts.filterMap fun stmt =>
    match stmt with
    | .ExpressionStatement _ expr =>
      if isCallTo "_strata_invariant" expr then extractCallArg expr
      else none
    | _ => none

/-- Rewrite mapping state variable references in an old() expression to their
    `_in` input parameter versions. For array state vars, also rewrite
    `name_length` to `name_length_in`.
    This desugars `old(balances[to])` to `select(balances_in, to)`. -/
partial def rewriteOldMappingRefs (mappingStateVars : List String) (arrayStateVars : List String)
    (expr : StmtExprMd) : StmtExprMd :=
  let rewrite (e : StmtExprMd) := rewriteOldMappingRefs mappingStateVars arrayStateVars e
  match expr.val with
  | .Identifier name =>
    if mappingStateVars.contains name.text then
      { expr with val := .Identifier s!"{name.text}_in" }
    else
      -- Check for array length references: name_length → name_length_in
      let isArrayLength := arrayStateVars.any fun av => name.text == s!"{av}_length"
      if isArrayLength then
        { expr with val := .Identifier s!"{name.text}_in" }
      else expr
  | .PrimitiveOp op args =>
    { expr with val := .PrimitiveOp op (args.map rewrite) }
  | .StaticCall callee args =>
    { expr with val := .StaticCall callee (args.map rewrite) }
  | .FieldSelect target fieldName =>
    { expr with val := .FieldSelect (rewrite target) fieldName }
  | .IfThenElse cond thenBr elseBr =>
    { expr with val := .IfThenElse (rewrite cond) (rewrite thenBr) (elseBr.map rewrite) }
  | .Forall param body =>
    -- Don't rewrite the bound variable if it shadows a mapping state var name
    let shadowedMappings := mappingStateVars.filter (· != param.name.text)
    let shadowedArrays := arrayStateVars.filter (· != param.name.text)
    { expr with val := .Forall param (rewriteOldMappingRefs shadowedMappings shadowedArrays body) }
  | .Exists param body =>
    let shadowedMappings := mappingStateVars.filter (· != param.name.text)
    let shadowedArrays := arrayStateVars.filter (· != param.name.text)
    { expr with val := .Exists param (rewriteOldMappingRefs shadowedMappings shadowedArrays body) }
  | _ => expr

mutual

/-- Translate a Solidity DDM node (expression context) to Laurel StmtExpr. -/
partial def translateExpr (ctx : TransCtx) (n : Solidity.node SourceRange)
    : Except TranslationError StmtExprMd := do
  match n with
  | .Identifier _ nameAnn =>
    -- Local variables and parameters shadow state variables
    if ctx.localNames.contains nameAnn.val then
      return mkStmtExprMd (.Identifier nameAnn.val)
    else if ctx.mappingStateVars.contains nameAnn.val then
      -- Mapping state vars are explicit parameters, not heap fields
      return mkStmtExprMd (.Identifier nameAnn.val)
    else if ctx.stateVarNames.contains nameAnn.val then
      return mkStmtExprMd (.FieldSelect (mkStmtExprMd (.Identifier "self")) nameAnn.val)
    else
      return mkStmtExprMd (.Identifier nameAnn.val)

  | .Literal _ valueAnn kindAnn =>
    match kindAnn.val with
    | "number" =>
      match valueAnn.val.toInt? with
      | some i => return mkStmtExprMd (.LiteralInt i)
      | none => throw (.typeError s!"Invalid number literal: {valueAnn.val}")
    | "bool" =>
      return mkStmtExprMd (.LiteralBool (valueAnn.val == "true"))
    | "string" =>
      return mkStmtExprMd (.LiteralString valueAnn.val)
    | k => throw (.unsupported s!"Literal kind: {k}")

  | .BinaryOperation _ left right opAnn => do
    let l ← translateExpr ctx left
    let r ← translateExpr ctx right
    let op ← match opAnn.val with
      | "+" => .ok Operation.Add
      | "-" => .ok Operation.Sub
      | "*" => .ok Operation.Mul
      | "/" => .ok Operation.Div
      | "%" => .ok Operation.Mod
      | "==" => .ok Operation.Eq
      | "!=" => .ok Operation.Neq
      | "<" => .ok Operation.Lt
      | "<=" => .ok Operation.Leq
      | ">" => .ok Operation.Gt
      | ">=" => .ok Operation.Geq
      | "&&" => .ok Operation.And
      | "||" => .ok Operation.Or
      | o => throw (.unsupported s!"Binary operator: {o}")
    return mkStmtExprMd (.PrimitiveOp op [l, r])

  | .UnaryOperation _ sub opAnn prefixAnn => do
    let subExpr ← translateExpr ctx sub
    if prefixAnn.val == "true" then
      match opAnn.val with
      | "!" => return mkStmtExprMd (.PrimitiveOp .Not [subExpr])
      | "-" => return mkStmtExprMd (.PrimitiveOp .Neg [subExpr])
      | "++" =>
        -- Prefix ++i: desugar to i = i + 1
        let one := mkStmtExprMd (.LiteralInt 1)
        let add := mkStmtExprMd (.PrimitiveOp .Add [subExpr, one])
        return mkStmtExprMd (.Assign [subExpr] add)
      | "--" =>
        -- Prefix --i: desugar to i = i - 1
        let one := mkStmtExprMd (.LiteralInt 1)
        let sub' := mkStmtExprMd (.PrimitiveOp .Sub [subExpr, one])
        return mkStmtExprMd (.Assign [subExpr] sub')
      | o => throw (.unsupported s!"Prefix unary operator: {o}")
    else
      -- Postfix operators (e.g., i++).
      -- NOTE: This desugaring produces the *new* value (i + 1), which is correct
      -- when i++ appears as a standalone statement. In expression context (e.g.,
      -- x = i++), Solidity evaluates to the *old* value. Phase 1 only supports
      -- statement-level usage; expression-context semantics require a temp variable
      -- and are deferred to a later phase.
      match opAnn.val with
      | "++" =>
        let one := mkStmtExprMd (.LiteralInt 1)
        let add := mkStmtExprMd (.PrimitiveOp .Add [subExpr, one])
        return mkStmtExprMd (.Assign [subExpr] add)
      | "--" =>
        let one := mkStmtExprMd (.LiteralInt 1)
        let sub' := mkStmtExprMd (.PrimitiveOp .Sub [subExpr, one])
        return mkStmtExprMd (.Assign [subExpr] sub')
      | o => throw (.unsupported s!"Postfix unary operator: {o}")

  | .FunctionCall sr fnExpr argsSeq kindAnn namesSeq => do
    -- Check the FunctionCall kind
    match kindAnn.val with
    | "structConstructorCall" =>
      -- Struct constructor: Point({x: a, y: b})
      -- Translate to StaticCall to a synthetic constructor.
      -- The constructor procedure is emitted by translateContract for each struct.
      let structName ← match fnExpr with
        | .Identifier _ nameAnn => pure nameAnn.val
        | _ => throw (.unsupported "struct constructor with non-Identifier expression")
      let args ← argsSeq.val.toList.mapM (translateExpr ctx)
      let names := namesSeq.val.toList.map (·.val)
      -- Reorder args to match struct field-declaration order.
      -- solc provides args in the order of the `names` array, but the
      -- synthetic constructor takes args in field-declaration order.
      let orderedArgs ← match ctx.structFields.lookup structName with
        | some fieldOrder =>
          let fieldNames := fieldOrder.map (·.1)
          if names.isEmpty then
            if args.length > 1 then
              throw (.internalError
                s!"structConstructorCall '{structName}' has {args.length} args but no names")
            else pure args
          else
            if names.length != fieldNames.length then
              throw (.internalError
                s!"struct constructor '{structName}' arity mismatch: \
                   {names.length} args but {fieldNames.length} fields")
            else
              let nameArgPairs := names.zip args
              fieldNames.mapM fun fieldName =>
                match nameArgPairs.lookup fieldName with
                | some arg => pure arg
                | none => throw (.internalError
                    s!"struct constructor missing field '{fieldName}'")
        | none => pure args
      return mkStmtExprMd (.StaticCall (s!"{structName}_constructor") orderedArgs)
    | "typeConversion" =>
      -- Type conversion: address(0), uint256(x), etc.
      -- Phase 1: identity cast (all integers are TInt)
      -- TODO: Preserve target type name as metadata/annotation so Phase 3
      -- bitvector work can identify conversion sites without re-parsing.
      let args ← argsSeq.val.toList.mapM (translateExpr ctx)
      match args with
      | [arg] => return arg
      | _ => throw (.typeError "Type conversion expects exactly one argument")
    | _ =>
    -- Regular function call (kind = "functionCall")
    match fnExpr with
    | .Identifier _ nameAnn =>
      let args ← argsSeq.val.toList.mapM (translateExpr ctx)
      match nameAnn.val with
      | "require" =>
        -- require(cond) or require(cond, msg) → assume(cond)
        -- No source metadata: assume nodes don't generate VCs
        match args with
        | cond :: _ => return mkStmtExprMd (.Assume cond)
        | [] => throw (.typeError "require() needs at least one argument")
      | "assert" =>
        match args with
        | [cond] => return mkStmtExprMdAnn ctx sr (.Assert cond)
        | _ => throw (.typeError "assert() expects exactly one argument")
      -- Strata specification functions (Option A from design doc)
      | "_strata_pre" =>
        -- Precondition: intercepted by translateFunction, not emitted as a statement.
        -- Return a marker that translateFunction will recognize and extract.
        -- TODO: If this call is not at the function body's top level (e.g., inside
        -- an if-branch), partitionSpecStmts won't extract it and it silently degrades
        -- to an Assume. Consider emitting a diagnostic when _strata_pre/_strata_post
        -- calls survive past partitionSpecStmts extraction.
        match args with
        | [cond] => return mkStmtExprMd (.Assume cond)  -- placeholder; extracted by translateFunction
        | _ => throw (.typeError "_strata_pre() expects exactly one argument")
      | "_strata_post" =>
        -- Postcondition: intercepted by translateFunction, not emitted as a statement.
        -- (Same caveat as _strata_pre: misplaced calls silently degrade to Assert.)
        match args with
        | [cond] => return mkStmtExprMd (.Assert cond)  -- placeholder; extracted by translateFunction
        | _ => throw (.typeError "_strata_post() expects exactly one argument")
      | "_strata_old" | "_strata_old_uint" | "_strata_old_int" | "_strata_old_bool" =>
        -- old(expr): reference pre-state values in postconditions.
        -- Desugared by rewriting mapping state variable references to their
        -- `_in` input parameter versions. Scalar state vars accessed via
        -- `FieldSelect self "name"` already refer to the pre-state (self is
        -- the input parameter). User parameters are already `_param` versions.
        -- ASSUMPTION: postcondition expressions are translated before any heap
        -- parameterization rewrites `self` references. If this ordering changes,
        -- `_strata_old` on scalar state variables may silently read current-state
        -- instead of pre-state. See test_old_scalar.sol for a regression test.
        match args with
        | [inner] =>
          let rewritten := rewriteOldMappingRefs ctx.mappingStateVars ctx.arrayStateVars inner
          return rewritten
        | _ => throw (.typeError s!"{nameAnn.val}() expects exactly one argument")
      | "_strata_loop_invariant" =>
        -- Loop invariant: intercepted by translateStmt for loops.
        -- Return a marker that the loop translation will recognize and extract.
        match args with
        | [cond] => return mkStmtExprMd (.Assert cond)  -- placeholder; extracted by loop translation
        | _ => throw (.typeError "_strata_loop_invariant() expects exactly one argument")
      | "_strata_invariant" =>
        -- Contract invariant: intercepted by translateContract.
        -- Return a marker that the contract translation will recognize and extract.
        match args with
        | [cond] => return mkStmtExprMd (.Assert cond)  -- placeholder; extracted by translateContract
        | _ => throw (.typeError "_strata_invariant() expects exactly one argument")
      | funcName =>
        -- Internal call to a non-pure function: thread `self`, `msg_sender`,
        -- and mapping/array state variables.
        -- Positional argument contract (must match callee signature in translateFunction):
        --   [self?, msg_sender, mapping_vars..., mapping_lengths..., user_args...]
        -- where user_args are received into `name_param` formals on the callee side.
        if ctx.nonPureFunctions.contains funcName then
          let mut implicitArgs : List StmtExprMd := []
          -- Thread self only if there are non-mapping state vars
          let nonMappingStateVars := ctx.stateVarNames.filter (!ctx.mappingStateVars.contains ·)
          if !nonMappingStateVars.isEmpty then
            implicitArgs := implicitArgs ++ [mkStmtExprMd (.Identifier "self")]
          implicitArgs := implicitArgs ++ [mkStmtExprMd (.Identifier "msg_sender")]
          -- Thread mapping/array state variables
          for name in ctx.mappingStateVars do
            implicitArgs := implicitArgs ++ [mkStmtExprMd (.Identifier name)]
            if ctx.arrayStateVars.contains name then
              implicitArgs := implicitArgs ++ [mkStmtExprMd (.Identifier s!"{name}_length")]
          return mkStmtExprMd (.StaticCall funcName (implicitArgs ++ args))
        else
          return mkStmtExprMd (.StaticCall funcName args)
    | .MemberAccess _ baseNode memberAnn =>
      -- Handle array.push(val) on array state variables
      if memberAnn.val == "push" then do
        let args ← argsSeq.val.toList.mapM (translateExpr ctx)
        -- Check if base is an array state variable
        let arrayName := match baseNode with
          | .Identifier _ nameAnn =>
            if ctx.arrayStateVars.contains nameAnn.val then some nameAnn.val
            else none
          | _ => none
        match arrayName with
        | some name =>
          -- Desugar: arr.push(v) → { arr := update(arr, arr_length, v); arr_length := arr_length + 1 }
          match args with
          | [val] =>
            let arrId := mkStmtExprMd (.Identifier name)
            let lenId := mkStmtExprMd (.Identifier s!"{name}_length")
            let store := mkStmtExprMd (.Assign [arrId]
              (mkStmtExprMd (.StaticCall "update" [arrId, lenId, val])))
            let one := mkStmtExprMd (.LiteralInt 1)
            let incr := mkStmtExprMd (.Assign [lenId]
              (mkStmtExprMd (.PrimitiveOp .Add [lenId, one])))
            return mkStmtExprMd (.Block [store, incr] none)
          | [] => throw (.unsupported "push() with no arguments (returns storage reference)")
          | _ => throw (.typeError "push() expects at most one argument")
        | none =>
          -- Fallback: generic push (not on a known array state var)
          let base ← translateExpr ctx baseNode
          match args with
          | [val] => return mkStmtExprMd (.StaticCall "array_push" [base, val])
          | [] => throw (.unsupported "push() with no arguments (returns storage reference)")
          | _ => throw (.typeError "push() expects at most one argument")
      else do
        -- General method call: obj.method(args) → StaticCall "method" (obj :: args)
        let base ← translateExpr ctx baseNode
        let args ← argsSeq.val.toList.mapM (translateExpr ctx)
        return mkStmtExprMd (.StaticCall memberAnn.val (base :: args))
    | .ElementaryTypeNameExpression _ typeNameAnn =>
      -- Type conversion: address(0), uint256(x), etc. → pass through the argument
      let args ← argsSeq.val.toList.mapM (translateExpr ctx)
      match args with
      | [arg] => return arg  -- identity cast for Phase 1 (all integers are TInt)
      | _ => throw (.typeError s!"Type cast {typeNameAnn.val}() expects exactly one argument")
    | _ =>
      return mkStmtExprMd .Hole  -- unsupported complex call target

  | .MemberAccess _ exprNode memberAnn => do
    -- msg.sender → Identifier "msg_sender" (implicit parameter)
    -- msg.X for X ≠ sender → unsupported
    match exprNode with
    | .Identifier _ baseNameAnn =>
      if baseNameAnn.val == "msg" then
        if memberAnn.val == "sender" then
          return mkStmtExprMd (.Identifier "msg_sender")
        else if memberAnn.val == "value" then
          return mkStmtExprMd (.Identifier "msg_value")
        else
          throw (.unsupported s!"msg.{memberAnn.val} (only msg.sender and msg.value are supported)")
      -- Storage alias field access: sender.field → Identifier "sender__field"
      match ctx.storageAliases.lookup baseNameAnn.val with
      | some _ => return mkStmtExprMd (.Identifier s!"{baseNameAnn.val}__{memberAnn.val}")
      | none => pure ()
      -- Array .length on state vars or memory array params → Identifier "name_length"
      if memberAnn.val == "length" then
        let name := baseNameAnn.val
        if ctx.arrayStateVars.contains name ||
           ctx.memoryArrayParams.contains name then
          return mkStmtExprMd (.Identifier s!"{name}_length")
    | _ => pure ()
    let obj ← translateExpr ctx exprNode
    if memberAnn.val == "length" then
      return mkStmtExprMd (.StaticCall "array_length" [obj])
    else
      return mkStmtExprMd (.FieldSelect obj memberAnn.val)

  | .IndexAccess _sr baseNode indexOpt => do
    let base ← translateExpr ctx baseNode
    match indexOpt with
    | .some_node _ idx => do
      let idxExpr ← translateExpr ctx idx
      -- TODO: Restore array index non-negativity check (assert idx >= 0).
      -- Previously wrapped in a Block expression which caused downstream
      -- FieldSelect resolution failures. The correct fix is to emit the
      -- assert as a preceding statement in translateBlockStmts, but this
      -- requires careful handling of: (1) side-effectful index expressions
      -- (function calls), (2) loop contexts where the index variable may
      -- not yet be constrained, and (3) storage-ref fields that are
      -- unconstrained due to heap parameterization (see Bug #2).
      -- See collectArrayIndexNodes/collectArrayIndexNodesStmt helpers.
      return mkStmtExprMd (.StaticCall "select" [base, idxExpr])
    | .missing_node _ =>
      throw (.unsupported "IndexAccess without index")

  | .Assignment _ lhs rhs opAnn => do
    let rhsExpr ← translateExpr ctx rhs
    -- Handle IndexAccess on LHS: map/array writes via select/update
    match collectIndexChain lhs with
    | some (rootNode, indices) => do
      let rootExpr ← translateExpr ctx rootNode
      let idxExprs ← indices.mapM (translateExpr ctx)
      -- Build the read expression: select(select(root, k1), k2) ...
      let readExpr := idxExprs.foldl (fun acc idx =>
        mkStmtExprMd (.StaticCall "select" [acc, idx])) rootExpr
      -- Compute the value to store
      let rhs' ← match opAnn.val with
        | "=" => pure rhsExpr
        | "+=" => pure (mkStmtExprMd (.PrimitiveOp .Add [readExpr, rhsExpr]))
        | "-=" => pure (mkStmtExprMd (.PrimitiveOp .Sub [readExpr, rhsExpr]))
        | "*=" => pure (mkStmtExprMd (.PrimitiveOp .Mul [readExpr, rhsExpr]))
        | "/=" => pure (mkStmtExprMd (.PrimitiveOp .Div [readExpr, rhsExpr]))
        | "%=" => pure (mkStmtExprMd (.PrimitiveOp .Mod [readExpr, rhsExpr]))
        | o => throw (.unsupported s!"Assignment operator: {o}")
      -- Build nested update: for m[k1][k2] = v, produce
      --   Assign [root] (update(root, k1, update(select(root, k1), k2, v)))
      let updateExpr ← buildNestedUpdate rootExpr idxExprs rhs'
      return mkStmtExprMd (.Assign [rootExpr] updateExpr)
    | none =>
    let lhsExpr ← translateExpr ctx lhs
    let rhs' ← match opAnn.val with
      | "=" => pure rhsExpr
      | "+=" => pure (mkStmtExprMd (.PrimitiveOp .Add [lhsExpr, rhsExpr]))
      | "-=" => pure (mkStmtExprMd (.PrimitiveOp .Sub [lhsExpr, rhsExpr]))
      | "*=" => pure (mkStmtExprMd (.PrimitiveOp .Mul [lhsExpr, rhsExpr]))
      | "/=" => pure (mkStmtExprMd (.PrimitiveOp .Div [lhsExpr, rhsExpr]))
      | "%=" => pure (mkStmtExprMd (.PrimitiveOp .Mod [lhsExpr, rhsExpr]))
      | o => throw (.unsupported s!"Assignment operator: {o}")
    return mkStmtExprMd (.Assign [lhsExpr] rhs')

  | _ => throw (.unsupported s!"Expression node type")

/-- Translate a list of statements in a block, threading storage alias context.
    Storage reference declarations (`Voter storage sender = voters[msg.sender]`)
    are not emitted as LocalVariable nodes; instead, the alias is recorded in
    the context so that subsequent reads/writes through the alias are desugared
    to operations on the underlying mapping entry. -/
partial def translateBlockStmts (ctx : TransCtx) (stmts : List (Solidity.node SourceRange))
    : Except TranslationError (List StmtExprMd) := do
  match stmts with
  | [] => return []
  | stmt :: rest =>
    match isStorageRefDecl stmt with
    | some (aliasName, initOpt) =>
      -- Storage reference: emit per-field scalar local variables initialized
      -- from the mapping entry.
      -- E.g., `Voter storage sender = voters[msg.sender]` becomes:
      --   LocalVariable "sender__weight" TInt (select(voters, msg_sender)#weight)
      --   LocalVariable "sender__voted" TBool (select(voters, msg_sender)#voted)
      --
      -- LIMITATION: The FieldSelect initialization (e.g., select(voters, msg_sender)#weight)
      -- is transformed by HeapParameterization into readField($heap, ..., Field), which
      -- returns an unconstrained value unless the field was previously written via
      -- updateField. This means reads of storage-reference fields may be weaker than
      -- the intended "initialized from the mapping entry" semantics.
      -- TODO: Either (a) emit explicit assume statements to constrain the field values,
      -- or (b) bypass heap parameterization for these FieldSelect nodes.
      --
      -- Writes to alias fields (e.g., `sender.voted = true`) modify the local
      -- variables. A write-back pass at the end of the enclosing block would be
      -- needed for full storage-reference semantics; for now, writes to the
      -- alias do NOT propagate back to the mapping. This is sound for
      -- verification (we verify a weaker program) but may produce false
      -- negatives for properties that depend on the write-back.
      let initExpr ← match initOpt with
        | .some_node _ initNode => translateExpr ctx initNode
        | .missing_node _ => throw (.unsupported "storage reference without initializer")
      -- Determine the struct type and its fields
      let structTypeName ← match extractStorageRefTypeName stmt with
        | some name => pure name
        | none => throw (.typeError "storage reference must have a user-defined struct type")
      let fieldInfo ← match ctx.structFields.lookup structTypeName with
        | some info => pure info
        | none => throw (.internalError s!"unknown struct type '{structTypeName}' for storage reference")
      -- Emit per-field local variables initialized from the mapping entry.
      -- Each field is initialized with FieldSelect on the mapping select result,
      -- e.g., sender__weight := select(voters, msg_sender)#weight
      let fieldDecls := fieldInfo.map fun (fieldName, fieldType) =>
        let fieldInit := mkStmtExprMd (.FieldSelect initExpr fieldName)
        mkStmtExprMd (.LocalVariable s!"{aliasName}__{fieldName}" (mkHighTypeMd fieldType) (some fieldInit))
      let alias : StorageAlias := { structTypeName, fields := fieldInfo }
      let fieldLocalNames := fieldInfo.map fun (fieldName, _) => s!"{aliasName}__{fieldName}"
      let ctx' := { ctx with storageAliases := ctx.storageAliases ++ [(aliasName, alias)],
                             localNames := ctx.localNames ++ fieldLocalNames }
      let rest' ← translateBlockStmts ctx' rest
      return fieldDecls ++ rest'
    | none =>
      -- Track local variable declarations for shadowing
      let ctx' := match stmt with
        | .VariableDeclarationStatement _ declsSeq _ =>
          match declsSeq.val.toList with
          | [.some_node _ (.VariableDeclaration _ nameAnn _ _ _ _)] =>
            { ctx with localNames := ctx.localNames ++ [nameAnn.val] }
          | _ => ctx
        | _ => ctx
      let s ← translateStmt ctx' stmt
      let rest' ← translateBlockStmts ctx' rest
      return s :: rest'

/-- Extract _strata_loop_invariant calls from a loop body and translate them.
    Returns (invariantExprs, translatedBody). -/
partial def extractAndTranslateLoopInvariants (ctx : TransCtx) (body : Solidity.node SourceRange)
    : Except TranslationError (List StmtExprMd × StmtExprMd) :=
  match body with
  | .Block _ stmtsSeq => do
    let (invNodes, restStmts) := extractLoopInvariants stmtsSeq.val.toList
    let invExprs ← invNodes.filterMapM fun n => do
      match extractCallArg n with
      | some argNode => some <$> translateExpr ctx argNode
      | none => pure none
    let restBody ← translateBlockStmts ctx restStmts
    pure (invExprs, mkStmtExprMd (.Block restBody none))
  | _ => do
    let b ← translateStmt ctx body
    pure ([], b)

/-- Translate a Solidity DDM node (statement context) to Laurel StmtExpr. -/
partial def translateStmt (ctx : TransCtx) (n : Solidity.node SourceRange)
    : Except TranslationError StmtExprMd := do
  match n with
  | .Block _ stmtsSeq => do
    let stmts ← translateBlockStmts ctx stmtsSeq.val.toList
    return mkStmtExprMd (.Block stmts none)

  -- Phase 1: treat unchecked blocks as regular blocks.
  -- TODO: suppress overflow checks for arithmetic inside unchecked blocks.
  | .UncheckedBlock _ stmtsSeq => do
    let stmts ← translateBlockStmts ctx stmtsSeq.val.toList
    return mkStmtExprMd (.Block stmts none)

  | .ExpressionStatement _ expr => translateExpr ctx expr

  | .Return _ exprOpt =>
    match exprOpt with
    | .some_node _ expr => do
      let e ← translateExpr ctx expr
      return mkStmtExprMd (.Return (some e))
    | .missing_node _ =>
      return mkStmtExprMd (.Return none)

  | .IfStatement _ cond thenBody elseOpt => do
    let condExpr ← translateExpr ctx cond
    let thenStmt ← translateStmt ctx thenBody
    let elseStmt ← match elseOpt with
      | .some_node _ elseBody => do
        let e ← translateStmt ctx elseBody
        pure (some e)
      | .missing_node _ => pure none
    return mkStmtExprMd (.IfThenElse condExpr thenStmt elseStmt)

  | .WhileStatement _ cond body => do
    let condExpr ← translateExpr ctx cond
    let (invariants, bodyStmt) ← extractAndTranslateLoopInvariants ctx body
    return mkStmtExprMd (.While condExpr invariants none bodyStmt)

  | .ForStatement _ initOpt condOpt loopOpt body => do
    -- Desugar: for (init; cond; loop) body → { init; while (cond) { body; loop } }
    let mut stmts : List StmtExprMd := []
    -- Init
    match initOpt with
    | .some_node _ initNode => do
      let s ← translateStmt ctx initNode
      stmts := [s]
    | .missing_node _ => pure ()
    -- Condition (default to true if missing)
    let condExpr ← match condOpt with
      | .some_node _ condNode => translateExpr ctx condNode
      | .missing_node _ => pure (mkStmtExprMd (.LiteralBool true))
    -- Extract _strata_loop_invariant calls from the loop body
    let (invariants, bodyStmt) ← extractAndTranslateLoopInvariants ctx body
    -- Loop body + increment
    let loopBody ← match loopOpt with
      | .some_node _ loopNode => do
        let loopStmt ← translateStmt ctx loopNode
        pure (mkStmtExprMd (.Block [bodyStmt, loopStmt] none))
      | .missing_node _ => pure bodyStmt
    let whileStmt := mkStmtExprMd (.While condExpr invariants none loopBody)
    stmts := stmts ++ [whileStmt]
    return mkStmtExprMd (.Block stmts none)

  | .VariableDeclarationStatement _ declsSeq initOpt => do
    -- Extract variable declarations
    let decls := declsSeq.val.toList
    match decls with
    | [] => throw (.internalError "Empty VariableDeclarationStatement")
    | [declOpt] =>
      match declOpt with
      | .some_node _ (.VariableDeclaration _ nameAnn typeNameOpt _stateVar _const storageLocAnn) =>
        let solTy := match typeNameOpt with
          | .some_type_name _ tn => translateTypeNode tn
          | .missing_type_name _ => { highType := mkHighTypeMd .TInt, solName := "uint256" }
        let initVal ← match initOpt with
          | .some_node _ initNode => do
            let e ← translateExpr ctx initNode
            pure (some e)
          | .missing_node _ => pure none
        -- Storage reference declarations are handled by translateBlockStmts
        -- (alias recorded in context, no LocalVariable emitted).
        -- If we reach here, it's a non-storage local variable.
        if storageLocAnn.val == "storage" then
          throw (.internalError "storage ref should be handled by translateBlockStmts")
        else
          return mkStmtExprMd (.LocalVariable nameAnn.val solTy.highType initVal)
      | .some_node _ _ =>
        throw (.unsupported "Non-VariableDeclaration in VariableDeclarationStatement")
      | .missing_node _ =>
        throw (.unsupported "Missing declaration in VariableDeclarationStatement")
    | _ =>
      throw (.unsupported "Tuple/multi-variable declarations (e.g., (uint a, uint b) = ...)")

  | .Assignment _ _ _ _ => translateExpr ctx n

  -- Expression nodes that appear as statements (e.g., function calls, postfix ops)
  | _ => translateExpr ctx n

end

/-! ## Function Translation -/

/-- Rewrite identifiers in a StmtExprMd: replace user parameter names with their
    `_param` suffixed versions for use in postconditions. Postconditions reference
    the original (immutable) input values, which are named `name_param` in Core. -/
partial def rewriteParamRefs (paramNames : List String) (expr : StmtExprMd) : StmtExprMd :=
  let rewrite (e : StmtExprMd) := rewriteParamRefs paramNames e
  match expr.val with
  | .Identifier name =>
    if paramNames.contains name.text then
      { expr with val := .Identifier s!"{name.text}_param" }
    else expr
  | .PrimitiveOp op args =>
    { expr with val := .PrimitiveOp op (args.map rewrite) }
  | .StaticCall callee args =>
    { expr with val := .StaticCall callee (args.map rewrite) }
  | .Old value =>
    { expr with val := .Old (rewrite value) }
  | .FieldSelect target fieldName =>
    { expr with val := .FieldSelect (rewrite target) fieldName }
  | .IfThenElse cond thenBr elseBr =>
    { expr with val := .IfThenElse (rewrite cond) (rewrite thenBr) (elseBr.map rewrite) }
  | .Forall param body =>
    -- Don't rewrite the bound variable if it shadows a parameter name
    let shadowed := paramNames.filter (· != param.name.text)
    { expr with val := .Forall param (rewriteParamRefs shadowed body) }
  | .Exists param body =>
    let shadowed := paramNames.filter (· != param.name.text)
    { expr with val := .Exists param (rewriteParamRefs shadowed body) }
  | _ => expr

/-- Translate a Solidity FunctionDefinition to a Laurel Procedure.
    Positional argument contract for non-pure functions (must match call site in translateExpr):
      [self?, msg_sender, mapping_vars..., mapping_lengths..., user_args_as_name_param...]
    where `self` is present only if there are non-mapping state variables. -/
def translateFunction (ctx : TransCtx) (fn : Solidity.node SourceRange)
    : Except TranslationError Procedure := do
  match fn with
  | .FunctionDefinition _ nameAnn kindAnn mutAnn _visAnn params retParams bodyOpt docAnn => do
    let isConstructor := kindAnn.val == "constructor"
    let funcName := if isConstructor then s!"{ctx.contractName}_ctor"
                    else nameAnn.val
    let isPure := mutAnn.val == "pure"
    let isView := mutAnn.val == "view"

    -- Translate parameters, tracking Solidity types for bounds
    let mut inputs : List Parameter := []
    let mut preconditions : List StmtExprMd := []

    -- Add implicit self parameter for non-pure functions with contract state
    -- Only add self for non-mapping state vars (mapping vars are separate params)
    let nonMappingStateVars := ctx.stateVarNames.filter (!ctx.mappingStateVars.contains ·)
    let hasNonMappingState := !nonMappingStateVars.isEmpty
    if !isPure && hasNonMappingState && !isConstructor then
      inputs := inputs ++ [{ name := "self",
                              type := mkHighTypeMd (.UserDefined ⟨ctx.contractName, none⟩) }]

    -- Add implicit msg_sender parameter for non-pure functions
    if !isPure then
      inputs := inputs ++ [{ name := "msg_sender", type := mkHighTypeMd .TInt }]
      preconditions := preconditions ++ [mkNonNegPrecond "msg_sender"]
      inputs := inputs ++ [{ name := "msg_value", type := mkHighTypeMd .TInt }]
      preconditions := preconditions ++ [mkNonNegPrecond "msg_value"]

    -- Add mapping/array state variables as explicit input parameters
    -- For view functions: use field name directly (read-only, no output).
    -- For non-view: use `name_in` for inputs; body assigns `name := name_in`.
    if !isPure && !isConstructor then
      for field in ctx.contractFields do
        if ctx.mappingStateVars.contains field.name.text then
          if isView then
            inputs := inputs ++ [{ name := field.name, type := field.type }]
          else
            inputs := inputs ++ [{ name := s!"{field.name.text}_in", type := field.type }]
          -- For array state vars, also add a length parameter
          if ctx.arrayStateVars.contains field.name.text then
            let lenName := if isView then s!"{field.name.text}_length"
                           else s!"{field.name.text}_length_in"
            inputs := inputs ++ [{ name := lenName, type := mkHighTypeMd .TInt }]
            preconditions := preconditions ++ [mkNonNegPrecond lenName]

    -- Track memory array parameters for paired length params
    let mut memoryArrayParamNames : List String := []
    -- Track user-provided parameter names and types for local copy generation.
    -- In Solidity, function parameters are mutable local copies; in Laurel/Core,
    -- input parameters are immutable. We rename inputs to `name_param` and create
    -- local variables `name := name_param` at the start of the body.
    let mut userParamInfo : List (String × HighTypeMd) := []

    match params with
    | .ParameterList _ paramsSeq =>
      for param in paramsSeq.val do
        match param with
        | .VariableDeclaration _ pName typeNameOpt _ _ storageLocAnn =>
          let solTy := match typeNameOpt with
            | .some_type_name _ tn => translateTypeNode tn
            | .missing_type_name _ => { highType := mkHighTypeMd .TInt, solName := "uint256" }
          -- Rename user parameter to `name_param` so we can create a mutable local copy
          let inputName := s!"{pName.val}_param"
          inputs := inputs ++ [{ name := inputName, type := solTy.highType }]
          userParamInfo := userParamInfo ++ [(pName.val, solTy.highType)]
          -- Add non-negative precondition for uint, address, and bytes types
          if solTy.isUint || solTy.isAddress || solTy.isBytes then
            preconditions := preconditions ++ [mkNonNegPrecond inputName]
          -- For memory array parameters, add a paired length parameter
          if solTy.solName == "array" &&
             (storageLocAnn.val == "memory" || storageLocAnn.val == "calldata") then
            let lenName := s!"{pName.val}_length"
            inputs := inputs ++ [{ name := lenName, type := mkHighTypeMd .TInt }]
            preconditions := preconditions ++ [mkNonNegPrecond lenName]
            memoryArrayParamNames := memoryArrayParamNames ++ [pName.val]
        | _ => throw (.unsupported "Non-VariableDeclaration in parameter list")
    | _ => throw (.internalError "Expected ParameterList for parameters")

    -- Translate return parameters
    let baseOutputs ← match retParams with
      | .ParameterList _ retSeq =>
        retSeq.val.toList.mapM fun param =>
          match param with
          | .VariableDeclaration _ pName typeNameOpt _ _ _ =>
            let solTy := match typeNameOpt with
              | .some_type_name _ tn => translateTypeNode tn
              | .missing_type_name _ => { highType := mkHighTypeMd .TInt, solName := "uint256" }
            let outName := if pName.val.isEmpty then "result" else pName.val
            pure ({ name := outName, type := solTy.highType } : Parameter)
          | _ => throw (.unsupported "Non-VariableDeclaration in return parameters")
      | _ => throw (.internalError "Expected ParameterList for return parameters")

    -- For constructors, add contract state fields as implicit output parameters
    let mut outputs := if isConstructor then
      let fieldOutputs := ctx.contractFields.map fun f =>
        ({ name := f.name, type := f.type } : Parameter)
      -- Also add array length outputs for array state vars
      let arrayLenOutputs := ctx.arrayStateVars.map fun name =>
        ({ name := s!"{name}_length", type := mkHighTypeMd .TInt } : Parameter)
      baseOutputs ++ fieldOutputs ++ arrayLenOutputs
    else baseOutputs

    -- Add mapping state variables as output parameters for non-pure, non-view functions
    if !isPure && !isView && !isConstructor then
      for field in ctx.contractFields do
        if ctx.mappingStateVars.contains field.name.text then
          outputs := outputs ++ [{ name := field.name, type := field.type }]
          -- For array state vars, also add a length output
          if ctx.arrayStateVars.contains field.name.text then
            outputs := outputs ++ [{ name := s!"{field.name.text}_length",
                                     type := mkHighTypeMd .TInt }]

    -- Translate body with parameter names in scope (for shadowing state vars)
    let paramNames := inputs.map (·.name.text)
    -- Output parameter names are also in scope (they shadow state vars).
    -- This is critical for constructors where scalar state vars are outputs.
    let outputNames := outputs.map (·.name.text)
    -- For non-view functions, mapping output names are also in scope
    let mappingOutputNames := if !isPure && !isView && !isConstructor then
      ctx.mappingStateVars
    else []
    -- Array length output names are also in scope
    let arrayLengthOutputNames := if !isPure then
      ctx.arrayStateVars.map (· ++ "_length")
    else []
    let bodyCtx := { ctx with localNames := ctx.localNames ++ paramNames ++ outputNames ++ mappingOutputNames ++ arrayLengthOutputNames ++ userParamInfo.map (·.1),
                              memoryArrayParams := memoryArrayParamNames }
    let (specPres, _specPosts, body, contractInvariants) ← match bodyOpt with
      | .some_node _ bodyNode => do
        -- Parse @custom:strata annotations from NatSpec documentation
        let annotations := parseStrataAnnotations docAnn.val
        let natspecPres := annotations.filterMap fun
          | .requires e => some e | _ => none
        let natspecPosts := annotations.filterMap fun
          | .ensures e => some e | _ => none

        -- Also extract _strata_pre/_strata_post from body for backward compatibility
        let (legacyPreNodes, legacyPostNodes, remainingStmts) ← match bodyNode with
          | .Block _ stmtsSeq => pure (partitionSpecStmts stmtsSeq.val.toList)
          | _ => pure ([], [], [bodyNode])

        -- Parse NatSpec spec expressions
        let natspecPreExprs ← natspecPres.mapM parseSpecExpr
        let natspecPostExprs ← natspecPosts.mapM fun s => do
          let expr ← parseSpecExpr s
          pure (processOldMarkers ctx.mappingStateVars ctx.arrayStateVars expr)

        -- Translate legacy _strata_* spec expressions (backward compat)
        let legacyPreExprs ← legacyPreNodes.filterMapM fun n => do
          match extractCallArg n with
          | some argNode => some <$> translateExpr bodyCtx argNode
          | none => pure none
        let legacyPostExprs ← legacyPostNodes.filterMapM fun n => do
          match extractCallArg n with
          | some argNode => some <$> translateExpr bodyCtx argNode
          | none => pure none

        -- Combine NatSpec + legacy specs
        let specPreExprs := natspecPreExprs ++ legacyPreExprs
        let specPostExprs := natspecPostExprs ++ legacyPostExprs

        -- Rewrite precondition expressions: user parameter names → _param names
        -- and mapping state var names → _in names (preconditions reference pre-state)
        let userParamNames := userParamInfo.map (·.1)
        let specPreExprs := specPreExprs.map (rewriteParamRefs userParamNames)
        let specPreExprs := if !isPure && !isView && !isConstructor then
          specPreExprs.map (rewriteOldMappingRefs ctx.mappingStateVars ctx.arrayStateVars)
        else specPreExprs
        -- Rewrite postcondition expressions: user parameter names → _param names
        let specPostExprs := specPostExprs.map (rewriteParamRefs userParamNames)
        -- Translate remaining body statements using translateBlockStmts
        let bodyStmts ← translateBlockStmts bodyCtx remainingStmts
        let b := mkStmtExprMd (.Block bodyStmts none)
        -- Build preamble: local copies of user params + mapping init assigns
        let mut preamble : List StmtExprMd := []
        -- 1. Local copies of user-provided parameters (Solidity params are mutable)
        for (name, ty) in userParamInfo do
          preamble := preamble ++ [mkStmtExprMd (.LocalVariable name ty
            (some (mkStmtExprMd (.Identifier ((s!"{name}_param" : String) : Identifier)))))]
        -- 2. Constructor default storage initialization (Solidity zero-inits all state)
        if isConstructor then
          for field in ctx.contractFields do
            let defaultVal := defaultValueForType field.type
            preamble := preamble ++ [mkStmtExprMd (.Assign
              [mkStmtExprMd (.Identifier (field.name.text : Identifier))]
              defaultVal)]
            -- For array state vars, also initialize length to 0
            if ctx.arrayStateVars.contains field.name.text then
              preamble := preamble ++ [mkStmtExprMd (.Assign
                [mkStmtExprMd (.Identifier ((s!"{field.name.text}_length" : String) : Identifier))]
                (mkStmtExprMd (.LiteralInt 0)))]
        -- 3. Mapping state var init assigns (name := name_in)
        if !isPure && !isView && !isConstructor && !ctx.mappingStateVars.isEmpty then
          for name in ctx.mappingStateVars do
            preamble := preamble ++ [mkStmtExprMd (.Assign
              [mkStmtExprMd (.Identifier (name : Identifier))]
              (mkStmtExprMd (.Identifier ((s!"{name}_in" : String) : Identifier))))]
            if ctx.arrayStateVars.contains name then
              preamble := preamble ++ [mkStmtExprMd (.Assign
                [mkStmtExprMd (.Identifier ((s!"{name}_length" : String) : Identifier))]
                (mkStmtExprMd (.Identifier ((s!"{name}_length_in" : String) : Identifier))))]
        let bodyExpr := if preamble.isEmpty then b
          else mkStmtExprMd (.Block (preamble ++ [b]) none)
        -- Translate contract invariant nodes once in this function's body context,
        -- then reuse for both pre- and postconditions. This avoids redundant
        -- effectful translation and prevents divergence if translateExpr gains
        -- side effects (e.g., fresh name generation).
        -- Contract invariants only apply to non-pure, non-view functions (and constructors
        -- for postconditions only). View functions cannot modify state, so they need not
        -- re-establish the invariant.
        let contractInvariants ← if isPure || isView then pure []
          else ctx.contractInvariantNodes.mapM (translateExpr bodyCtx)
        -- Add NatSpec invariants
        let contractInvariants := contractInvariants ++ (if isPure || isView then [] else ctx.contractInvariantNatspec)
        -- Rewrite invariant expressions: user parameter names → _param names
        let contractInvariants := contractInvariants.map (rewriteParamRefs userParamNames)
        -- If postconditions are present, use Body.Opaque; otherwise Body.Transparent
        let allPosts := specPostExprs ++ contractInvariants
        if allPosts.isEmpty then
          pure (specPreExprs, [], Body.Transparent bodyExpr, contractInvariants)
        else
          pure (specPreExprs, allPosts, Body.Opaque allPosts (some bodyExpr) [], contractInvariants)
      | .missing_node _ =>
        -- No body: translate invariants with base context (no locals)
        let contractInvariants ← if isPure || isView then pure []
          else ctx.contractInvariantNodes.mapM (translateExpr ctx)
        let contractInvariants := contractInvariants ++ (if isPure || isView then [] else ctx.contractInvariantNatspec)
        pure ([], contractInvariants, if contractInvariants.isEmpty then .Abstract []
          else .Abstract contractInvariants, contractInvariants)

    -- Reuse the already-translated contract invariants for preconditions.
    -- Contract invariants as preconditions apply to non-pure, non-constructor functions.
    -- (Constructors establish the invariant; they don't assume it.)
    let applicableInvariantPres := if isPure || isView || isConstructor then []
      else contractInvariants
    let allPreconditions := preconditions ++ specPres ++ applicableInvariantPres

    return {
      name := funcName
      inputs := inputs
      outputs := outputs
      preconditions := allPreconditions
      determinism := .deterministic none
      decreases := none
      isFunctional := false
      body := body
      md := default
    }
  | _ => throw (.internalError "Expected FunctionDefinition")

/-! ## Contract Translation -/

/-- Translate a VariableDeclaration to a Laurel Field.
    Shared helper for struct members and state variables.
    Reads the `constant` annotation to set `isMutable` correctly. -/
def translateFieldDecl (errCtx : String) (member : Solidity.node SourceRange)
    : Except TranslationError Field := do
  match member with
  | .VariableDeclaration _ nameAnn typeNameOpt _ constAnn _ =>
    let solTy ← match typeNameOpt with
      | .some_type_name _ tn => pure (translateTypeNode tn)
      | .missing_type_name _ => throw (.internalError s!"{errCtx} missing type name")
    return { name := nameAnn.val, isMutable := constAnn.val != "true", type := solTy.highType }
  | _ => throw (.internalError s!"Expected VariableDeclaration for {errCtx}")

/-- Translate a Solidity ContractDefinition to Laurel types and procedures.
    Contracts become a CompositeType with state variables as fields;
    functions are emitted as static procedures.
    Two-pass: first collect struct definitions (for field order), then translate functions. -/
def translateContract (ctx : TransCtx) (contract : Solidity.node SourceRange)
    : Except TranslationError (List Procedure × List TypeDefinition) := do
  match contract with
  | .ContractDefinition _ nameAnn _kindAnn nodesSeq contractDocAnn => do
    let mut procedures : List Procedure := []
    let mut fields : List Field := []
    let mut types : List TypeDefinition := []
    let mut structFieldMap : List (String × List (String × HighType)) := ctx.structFields

    -- Pass 1: collect struct definitions and state variables
    for member in nodesSeq.val do
      match member with
      | .StructDefinition _ sNameAnn membersSeq => do
        let sFields ← membersSeq.val.toList.mapM (translateFieldDecl "struct member")
        types := types ++ [.Composite {
          name := sNameAnn.val
          extending := []
          fields := sFields
          instanceProcedures := []
        }]
        -- Record field order for argument reordering
        structFieldMap := structFieldMap ++ [(sNameAnn.val, sFields.map fun f => (f.name.text, f.type.val))]
        -- Emit a synthetic constructor procedure for the struct.
        -- Signature: S_constructor(f1: T1, f2: T2, ...) returns (__ctor_result: S)
        -- Postconditions: __ctor_result.fi == fi for each field
        -- Uses "__ctor_result" to avoid collision with struct fields named "result".
        let ctorInputs := sFields.map fun f =>
          ({ name := f.name, type := f.type } : Parameter)
        let ctorOutput : Parameter :=
          { name := "__ctor_result", type := mkHighTypeMd (.UserDefined ⟨sNameAnn.val, none⟩) }
        let postconds := sFields.map fun f =>
          let resultField := mkStmtExprMd (.FieldSelect
            (mkStmtExprMd (.Identifier "__ctor_result")) f.name)
          let paramRef := mkStmtExprMd (.Identifier f.name)
          mkStmtExprMd (.PrimitiveOp .Eq [resultField, paramRef])
        procedures := procedures ++ [{
          name := s!"{sNameAnn.val}_constructor"
          inputs := ctorInputs
          outputs := [ctorOutput]
          preconditions := []
          determinism := .deterministic none
          decreases := none
          isFunctional := true
          body := .Abstract postconds
          md := default
        }]
      | .VariableDeclaration _ _ _ stateVarAnn _ _ =>
        if stateVarAnn.val == "true" then do
          let field ← translateFieldDecl "state variable" member
          fields := fields ++ [field]
        else
          pure ()
      | _ => pure ()

    -- Pass 2: collect non-pure function names for internal call resolution
    -- Only include public/internal functions; external functions cannot be called internally.
    let stateVarNames := fields.map (·.name.text)
    -- Identify mapping-typed state variables (these bypass the heap)
    let mappingStateVars := fields.filterMap fun f =>
      match f.type.val with
      | .TMap _ _ => some f.name.text
      | _ => none
    -- Identify array-typed state variables (subset of mappingStateVars).
    -- We re-scan the DDM nodes to distinguish ArrayTypeName from MappingType,
    -- since both translate to TMap in HighType.
    let mut arrayStateVars : List String := []
    for member in nodesSeq.val do
      match member with
      | .VariableDeclaration _ nameAnn typeNameOpt stateVarAnn _ _ =>
        if stateVarAnn.val == "true" then
          match typeNameOpt with
          | .some_type_name _ (.ArrayTypeName _ _) =>
            arrayStateVars := arrayStateVars ++ [nameAnn.val]
          | _ => pure ()
      | _ => pure ()
    let mut nonPureFunctions : List String := []
    for member in nodesSeq.val do
      match member with
      | .FunctionDefinition _ fnNameAnn fnKindAnn fnMutAnn fnVisAnn _ _ _ _ =>
        let fnIsPure := fnMutAnn.val == "pure"
        let fnIsConstructor := fnKindAnn.val == "constructor"
        let fnIsExternal := fnVisAnn.val == "external"
        if !fnIsPure && !fnIsConstructor && !fnIsExternal then
          nonPureFunctions := nonPureFunctions ++ [fnNameAnn.val]
      | _ => pure ()

    -- Pass 3: Extract contract invariants from constructor body
    -- _strata_invariant calls in the constructor are conjoined with every
    -- public function's pre- and postconditions.
    -- We store the raw DDM nodes and re-translate them per function context,
    -- so that state variable references resolve correctly in each function
    -- (e.g., as output parameters in the constructor, as FieldSelect self "name"
    -- in non-pure functions).
    let sfm := structFieldMap
    let baseFnCtx : TransCtx :=
      { ctx with structFields := sfm
                 contractName := nameAnn.val
                 contractFields := fields
                 stateVarNames := stateVarNames
                 mappingStateVars := mappingStateVars
                 arrayStateVars := arrayStateVars
                 nonPureFunctions := nonPureFunctions }
    let mut contractInvariantNodes : List (Solidity.node SourceRange) := []
    -- Parse @custom:strata invariant from contract NatSpec
    let contractAnnotations := parseStrataAnnotations contractDocAnn.val
    let natspecInvariantStrs := contractAnnotations.filterMap fun
      | .invariant e => some e | _ => none
    let natspecInvariantExprs ← natspecInvariantStrs.mapM parseSpecExpr
    for member in nodesSeq.val do
      match member with
      | .FunctionDefinition _ _ kindAnn _ _ _ _ bodyOpt _ =>
        if kindAnn.val == "constructor" then
          match bodyOpt with
          | .some_node _ (.Block _ stmtsSeq) =>
            contractInvariantNodes := extractContractInvariants stmtsSeq.val.toList
          | _ => pure ()
      | _ => pure ()

    -- Pass 4: translate functions with struct field info, state context, and invariant nodes
    -- Invariant nodes are re-translated per function so that state variable references
    -- resolve correctly in each function's context.
    let fnCtx := { baseFnCtx with contractInvariantNodes := contractInvariantNodes,
                                   contractInvariantNatspec := natspecInvariantExprs }
    for member in nodesSeq.val do
      match member with
      | .FunctionDefinition _ fnNameAnn _ _ _ _ _ _ _ => do
        -- Skip _strata_* stub functions (only needed for solc compilation)
        if fnNameAnn.val.startsWith "_strata_" then pure ()
        else do
          let proc ← translateFunction fnCtx member
          procedures := procedures ++ [proc]
      | _ => pure ()

    -- Contract invariants are checked via injection into public functions'
    -- pre/postconditions. No separate invariant procedure is needed.

    -- Emit a CompositeType for the contract only when it has non-mapping state-variable fields.
    -- Mapping fields are passed as explicit parameters, not stored on the heap.
    let nonMappingFields := fields.filter fun f => !mappingStateVars.contains f.name.text
    if !nonMappingFields.isEmpty then
      let contractType : TypeDefinition := .Composite {
        name := nameAnn.val
        extending := []
        fields := nonMappingFields
        instanceProcedures := []
      }
      types := types ++ [contractType]

    return (procedures, types)
  | _ => throw (.internalError "Expected ContractDefinition")

/-! ## Top-Level Translation -/

/-- Translate a Solidity SourceUnit (top-level AST) to a Laurel Program.
    `solFilePath` is the path to the original .sol file, used for source location metadata.
    Pass `none` to skip metadata construction. -/
def solidityToLaurel (cmd : Solidity.Command SourceRange) (solFilePath : Option String := none)
    : Except TranslationError Laurel.Program := do
  let ctx : TransCtx := { uri := solFilePath.map .file }
  match cmd with
  | .SourceUnit _ nodesSeq => do
    let mut allProcedures : List Procedure := []
    let mut allTypes : List TypeDefinition := []

    for node in nodesSeq.val do
      match node with
      | .ContractDefinition _ _ _ _ _ => do
        let (procs, types) ← translateContract ctx node
        allProcedures := allProcedures ++ procs
        allTypes := allTypes ++ types
      | .PragmaDirective _ _ => pure ()  -- Skip pragmas
      | _ => pure ()  -- Skip unsupported top-level nodes

    return {
      staticProcedures := allProcedures
      staticFields := []
      types := allTypes
      constants := []
    }

end Strata.Solidity
