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
  localNames : List String := []

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
      | funcName =>
        -- Internal call to a non-pure function: thread `self` and `msg_sender`
        if ctx.nonPureFunctions.contains funcName then
          let selfArg := mkStmtExprMd (.Identifier "self")
          let senderArg := mkStmtExprMd (.Identifier "msg_sender")
          return mkStmtExprMd (.StaticCall funcName (selfArg :: senderArg :: args))
        else
          return mkStmtExprMd (.StaticCall funcName args)
    | .MemberAccess _ baseNode memberAnn =>
      -- Handle array.push(val) on array state variables
      if memberAnn.val == "push" then do
        let args ← argsSeq.val.toList.mapM (translateExpr ctx)
        -- Check if base is an array state variable
        let arrayName := match baseNode with
          | .Identifier _ nameAnn =>
            if ctx.arrayStateVars.contains nameAnn.val &&
               !ctx.localNames.contains nameAnn.val then some nameAnn.val
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
        else
          throw (.unsupported s!"msg.{memberAnn.val} (only msg.sender is supported)")
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
      -- NOTE: No default-zero semantics for uninitialized mapping entries yet.
      -- For array-typed bases, emit assert(idx >= 0) since arrays are encoded as
      -- TMap TInt T but Solidity array indices (uint256) are always non-negative.
      -- Mapping-typed bases don't need this guard (keys can be any type).
      -- TODO: Restore array index non-negativity guard when array support is active.
      --       Requires checking base expression's type to distinguish arrays from mappings.
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
      -- Storage reference: emit per-field scalar local variables.
      -- E.g., `Voter storage sender = voters[msg.sender]` becomes:
      --   LocalVariable "sender__weight" TInt none
      --   LocalVariable "sender__voted" TBool none
      --
      -- TODO: Ideally each field should be initialized with
      --   FieldSelect(select(voters, msg_sender), "weight")
      -- but the Laurel pipeline's heap parameterization cannot resolve
      -- FieldSelect on a select() result (Map type, not Composite).
      -- For now, fields are left uninitialized (havoc'd). This is sound
      -- but may produce false negatives for properties that depend on
      -- the initial values read from the mapping.
      let _initExpr ← match initOpt with
        | .some_node _ initNode => translateExpr ctx initNode
        | .missing_node _ => throw (.unsupported "storage reference without initializer")
      -- Determine the struct type and its fields
      let structTypeName ← match extractStorageRefTypeName stmt with
        | some name => pure name
        | none => throw (.typeError "storage reference must have a user-defined struct type")
      let fieldInfo ← match ctx.structFields.lookup structTypeName with
        | some info => pure info
        | none => throw (.internalError s!"unknown struct type '{structTypeName}' for storage reference")
      -- Emit per-field local variables (uninitialized for now — see TODO above)
      let fieldDecls := fieldInfo.map fun (fieldName, fieldType) =>
        mkStmtExprMd (.LocalVariable s!"{aliasName}__{fieldName}" (mkHighTypeMd fieldType) none)
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

/-- Translate a Solidity DDM node (statement context) to Laurel StmtExpr. -/
partial def translateStmt (ctx : TransCtx) (n : Solidity.node SourceRange)
    : Except TranslationError StmtExprMd := do
  match n with
  | .Block _ stmtsSeq => do
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
    let bodyStmt ← translateStmt ctx body
    return mkStmtExprMd (.While condExpr [] none bodyStmt)

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
    -- Loop body + increment
    let bodyStmt ← translateStmt ctx body
    let loopBody ← match loopOpt with
      | .some_node _ loopNode => do
        let loopStmt ← translateStmt ctx loopNode
        pure (mkStmtExprMd (.Block [bodyStmt, loopStmt] none))
      | .missing_node _ => pure bodyStmt
    let whileStmt := mkStmtExprMd (.While condExpr [] none loopBody)
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

/-- Translate a Solidity FunctionDefinition to a Laurel Procedure. -/
def translateFunction (ctx : TransCtx) (fn : Solidity.node SourceRange)
    : Except TranslationError Procedure := do
  match fn with
  | .FunctionDefinition _ nameAnn kindAnn mutAnn _visAnn params retParams bodyOpt => do
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

    match params with
    | .ParameterList _ paramsSeq =>
      for param in paramsSeq.val do
        match param with
        | .VariableDeclaration _ pName typeNameOpt _ _ storageLocAnn =>
          let solTy := match typeNameOpt with
            | .some_type_name _ tn => translateTypeNode tn
            | .missing_type_name _ => { highType := mkHighTypeMd .TInt, solName := "uint256" }
          inputs := inputs ++ [{ name := pName.val, type := solTy.highType }]
          -- Add non-negative precondition for uint, address, and bytes types
          if solTy.isUint || solTy.isAddress || solTy.isBytes then
            preconditions := preconditions ++ [mkNonNegPrecond pName.val]
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
      baseOutputs ++ fieldOutputs
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
    -- For non-view functions, mapping output names are also in scope
    let mappingOutputNames := if !isPure && !isView && !isConstructor then
      ctx.mappingStateVars
    else []
    -- Array length output names are also in scope
    let arrayLengthOutputNames := if !isPure && !isView && !isConstructor then
      ctx.arrayStateVars.map (· ++ "_length")
    else if isView then
      ctx.arrayStateVars.map (· ++ "_length")
    else []
    let bodyCtx := { ctx with localNames := ctx.localNames ++ paramNames ++ mappingOutputNames ++ arrayLengthOutputNames,
                              memoryArrayParams := memoryArrayParamNames }
    let body ← match bodyOpt with
      | .some_node _ bodyNode => do
        let b ← Strata.Solidity.translateStmt bodyCtx bodyNode
        -- For non-view, non-pure functions with mapping state vars, prepend `name := name_in`
        if !isPure && !isView && !isConstructor && !ctx.mappingStateVars.isEmpty then
          let mut initAssigns : List StmtExprMd := []
          for name in ctx.mappingStateVars do
            initAssigns := initAssigns ++ [mkStmtExprMd (.Assign
              [mkStmtExprMd (.Identifier (name : Identifier))]
              (mkStmtExprMd (.Identifier ((s!"{name}_in" : String) : Identifier))))]
            -- For array state vars, also init the length variable
            if ctx.arrayStateVars.contains name then
              initAssigns := initAssigns ++ [mkStmtExprMd (.Assign
                [mkStmtExprMd (.Identifier ((s!"{name}_length" : String) : Identifier))]
                (mkStmtExprMd (.Identifier ((s!"{name}_length_in" : String) : Identifier))))]
          pure (.Transparent (mkStmtExprMd (.Block (initAssigns ++ [b]) none)))
        else
          pure (.Transparent b)
      | .missing_node _ =>
        pure (.Abstract [])

    return {
      name := funcName
      inputs := inputs
      outputs := outputs
      preconditions := preconditions
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
  | .ContractDefinition _ nameAnn _kindAnn nodesSeq => do
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
      | .FunctionDefinition _ fnNameAnn fnKindAnn fnMutAnn fnVisAnn _ _ _ =>
        let fnIsPure := fnMutAnn.val == "pure"
        let fnIsConstructor := fnKindAnn.val == "constructor"
        let fnIsExternal := fnVisAnn.val == "external"
        if !fnIsPure && !fnIsConstructor && !fnIsExternal then
          nonPureFunctions := nonPureFunctions ++ [fnNameAnn.val]
      | _ => pure ()

    -- Pass 3: translate functions with struct field info and state context available
    -- TODO: structFieldMap is local to each ContractDefinition. If a future
    -- Solidity version or import mechanism allows cross-contract struct
    -- references within the same file, this lookup will need to be lifted
    -- to the SourceUnit level.
    let fnCtx := { ctx with structFields := structFieldMap,
                            contractName := nameAnn.val,
                            contractFields := fields,
                            stateVarNames := stateVarNames,
                            mappingStateVars := mappingStateVars,
                            arrayStateVars := arrayStateVars,
                            nonPureFunctions := nonPureFunctions }
    for member in nodesSeq.val do
      match member with
      | .FunctionDefinition _ _ _ _ _ _ _ _ => do
        let proc ← translateFunction fnCtx member
        procedures := procedures ++ [proc]
      | _ => pure ()

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
      | .ContractDefinition _ _ _ _ => do
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
