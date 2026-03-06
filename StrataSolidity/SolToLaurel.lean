/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

import Strata.Languages.Laurel.Laurel
import Strata.Languages.Laurel.LaurelToCoreTranslator
import Strata.Languages.Core.Verifier
import Strata.Languages.Solidity.SolidityDialect
import Strata.Languages.Solidity.ReadSolidity

/-!
# Solidity AST → Laurel Translation (Phase 1)

Translates the Solidity DDM AST (produced by solc → solast.py → Ion)
into the Laurel intermediate representation.

## Phase 1 scope
- Pure/view functions with value types (uint256, int256, bool, address)
- `require(cond)` → assume, `assert(cond)` → assert
- if/else, while, for loops, return, variable declarations, assignments
- Arithmetic and comparison operators
- Contracts as CompositeType with fields + instance procedures

## Design (Option A from design doc)
Uses `solc --ast-json` via the external Python tooling; this module
only handles the Lean-side translation from typed DDM AST to Laurel.
-/

namespace Strata.Solidity

open Laurel

/-! ## Helpers -/

def defaultMetadata : Imperative.MetaData Core.Expression := #[]

def mkHighTypeMd (ty : HighType) : HighTypeMd :=
  { val := ty, md := defaultMetadata }

def mkStmtExprMd (expr : StmtExpr) : StmtExprMd :=
  { val := expr, md := defaultMetadata }

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
    Phase 1: uint256/int256 → TInt, bool → TBool, address → TInt. -/
def translateTypeName (name : String) : SolType :=
  if name == "bool" then { highType := mkHighTypeMd .TBool, solName := name }
  else if name == "address" then { highType := mkHighTypeMd .TInt, solName := name }
  else { highType := mkHighTypeMd .TInt, solName := name }

/-- Translate a DDM type_name node to SolType. -/
def translateTypeNode (tn : Solidity.type_name SourceRange) : SolType :=
  match tn with
  | .ElementaryTypeName _ nameAnn => translateTypeName nameAnn.val

/-- Is this a Solidity unsigned integer type? -/
def SolType.isUint (st : SolType) : Bool :=
  st.solName.startsWith "uint"

/-- Is this a Solidity address type? -/
def SolType.isAddress (st : SolType) : Bool :=
  st.solName == "address"

/-- Generate a non-negative precondition: param >= 0 -/
def mkNonNegPrecond (paramName : String) : StmtExprMd :=
  let ident := mkStmtExprMd (.Identifier paramName)
  let zero := mkStmtExprMd (.LiteralInt 0)
  mkStmtExprMd (.PrimitiveOp .Geq [ident, zero])

/-! ## Expression Translation -/

mutual

/-- Translate a Solidity DDM node (expression context) to Laurel StmtExpr. -/
partial def translateExpr (n : Solidity.node SourceRange)
    : Except TranslationError StmtExprMd := do
  match n with
  | .Identifier _ nameAnn =>
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
    let l ← translateExpr left
    let r ← translateExpr right
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
    let subExpr ← translateExpr sub
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

  | .FunctionCall _ fnExpr argsSeq _kindAnn => do
    -- Check for require/assert special forms
    match fnExpr with
    | .Identifier _ nameAnn =>
      let args ← argsSeq.val.toList.mapM translateExpr
      match nameAnn.val with
      | "require" =>
        -- require(cond) or require(cond, msg) → assume(cond)
        match args with
        | cond :: _ => return mkStmtExprMd (.Assume cond)
        | [] => throw (.typeError "require() needs at least one argument")
      | "assert" =>
        match args with
        | [cond] => return mkStmtExprMd (.Assert cond)
        | _ => throw (.typeError "assert() expects exactly one argument")
      | funcName =>
        return mkStmtExprMd (.StaticCall funcName args)
    | _ =>
      return mkStmtExprMd .Hole  -- unsupported complex call target

  | .MemberAccess _ exprNode memberAnn => do
    let obj ← translateExpr exprNode
    return mkStmtExprMd (.FieldSelect obj memberAnn.val)

  | .IndexAccess _ baseNode indexOpt => do
    let base ← translateExpr baseNode
    match indexOpt with
    | .some_node _ idx => do
      let idxExpr ← translateExpr idx
      -- Map read: m[k] → StaticCall "map_select" [m, k]
      return mkStmtExprMd (.StaticCall "map_select" [base, idxExpr])
    | .missing_node _ =>
      throw (.unsupported "IndexAccess without index")

  | .Assignment _ lhs rhs opAnn => do
    let lhsExpr ← translateExpr lhs
    let rhsExpr ← translateExpr rhs
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

/-- Translate a Solidity DDM node (statement context) to Laurel StmtExpr. -/
partial def translateStmt (n : Solidity.node SourceRange)
    : Except TranslationError StmtExprMd := do
  match n with
  | .Block _ stmtsSeq => do
    let stmts ← stmtsSeq.val.toList.mapM translateStmt
    return mkStmtExprMd (.Block stmts none)

  | .ExpressionStatement _ expr => translateExpr expr

  | .Return _ exprOpt =>
    match exprOpt with
    | .some_node _ expr => do
      let e ← translateExpr expr
      return mkStmtExprMd (.Return (some e))
    | .missing_node _ =>
      return mkStmtExprMd (.Return none)

  | .IfStatement _ cond thenBody elseOpt => do
    let condExpr ← translateExpr cond
    let thenStmt ← translateStmt thenBody
    let elseStmt ← match elseOpt with
      | .some_node _ elseBody => do
        let e ← translateStmt elseBody
        pure (some e)
      | .missing_node _ => pure none
    return mkStmtExprMd (.IfThenElse condExpr thenStmt elseStmt)

  | .WhileStatement _ cond body => do
    let condExpr ← translateExpr cond
    let bodyStmt ← translateStmt body
    return mkStmtExprMd (.While condExpr [] none bodyStmt)

  | .ForStatement _ initOpt condOpt loopOpt body => do
    -- Desugar: for (init; cond; loop) body → { init; while (cond) { body; loop } }
    let mut stmts : List StmtExprMd := []
    -- Init
    match initOpt with
    | .some_node _ initNode => do
      let s ← translateStmt initNode
      stmts := [s]
    | .missing_node _ => pure ()
    -- Condition (default to true if missing)
    let condExpr ← match condOpt with
      | .some_node _ condNode => translateExpr condNode
      | .missing_node _ => pure (mkStmtExprMd (.LiteralBool true))
    -- Loop body + increment
    let bodyStmt ← translateStmt body
    let loopBody ← match loopOpt with
      | .some_node _ loopNode => do
        let loopStmt ← translateStmt loopNode
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
      | .some_node _ (.VariableDeclaration _ nameAnn typeNameOpt _stateVar _const) =>
        let solTy := match typeNameOpt with
          | .some_type_name _ tn => translateTypeNode tn
          | .missing_type_name _ => { highType := mkHighTypeMd .TInt, solName := "uint256" }
        let initVal ← match initOpt with
          | .some_node _ initNode => do
            let e ← translateExpr initNode
            pure (some e)
          | .missing_node _ => pure none
        return mkStmtExprMd (.LocalVariable nameAnn.val solTy.highType initVal)
      | .some_node _ _ =>
        throw (.unsupported "Non-VariableDeclaration in VariableDeclarationStatement")
      | .missing_node _ =>
        throw (.unsupported "Missing declaration in VariableDeclarationStatement")
    | _ =>
      throw (.unsupported "Tuple/multi-variable declarations (e.g., (uint a, uint b) = ...)")

  | .Assignment _ _ _ _ => translateExpr n

  -- Expression nodes that appear as statements (e.g., function calls, postfix ops)
  | _ => translateExpr n

end

/-! ## Function Translation -/

/-- Translate a Solidity FunctionDefinition to a Laurel Procedure. -/
def translateFunction (fn : Solidity.node SourceRange)
    : Except TranslationError Procedure := do
  match fn with
  | .FunctionDefinition _ nameAnn _kindAnn _mutAnn _visAnn params retParams bodyOpt => do
    let funcName := nameAnn.val

    -- Translate parameters, tracking Solidity types for bounds
    let mut inputs : List Parameter := []
    let mut preconditions : List StmtExprMd := []

    match params with
    | .ParameterList _ paramsSeq =>
      for param in paramsSeq.val do
        match param with
        | .VariableDeclaration _ pName typeNameOpt _ _ =>
          let solTy := match typeNameOpt with
            | .some_type_name _ tn => translateTypeNode tn
            | .missing_type_name _ => { highType := mkHighTypeMd .TInt, solName := "uint256" }
          inputs := inputs ++ [{ name := pName.val, type := solTy.highType }]
          -- Add non-negative precondition for uint and address types
          if solTy.isUint || solTy.isAddress then
            preconditions := preconditions ++ [mkNonNegPrecond pName.val]
        | _ => throw (.unsupported "Non-VariableDeclaration in parameter list")
    | _ => throw (.internalError "Expected ParameterList for parameters")

    -- Translate return parameters
    let outputs ← match retParams with
      | .ParameterList _ retSeq =>
        retSeq.val.toList.mapM fun param =>
          match param with
          | .VariableDeclaration _ pName typeNameOpt _ _ =>
            let solTy := match typeNameOpt with
              | .some_type_name _ tn => translateTypeNode tn
              | .missing_type_name _ => { highType := mkHighTypeMd .TInt, solName := "uint256" }
            let outName := if pName.val.isEmpty then "result" else pName.val
            pure ({ name := outName, type := solTy.highType } : Parameter)
          | _ => throw (.unsupported "Non-VariableDeclaration in return parameters")
      | _ => throw (.internalError "Expected ParameterList for return parameters")

    -- Translate body
    let body ← match bodyOpt with
      | .some_node _ bodyNode => do
        let b ← translateStmt bodyNode
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

/-- Translate a Solidity ContractDefinition to Laurel types and procedures. -/
def translateContract (contract : Solidity.node SourceRange)
    : Except TranslationError (List Procedure × List TypeDefinition) := do
  match contract with
  | .ContractDefinition _ _nameAnn _kindAnn nodesSeq => do
    let mut procedures : List Procedure := []
    let mut types : List TypeDefinition := []

    for member in nodesSeq.val do
      match member with
      | .FunctionDefinition _ _ _ _ _ _ _ _ => do
        let proc ← translateFunction member
        procedures := procedures ++ [proc]
      | .VariableDeclaration _ _ _ _ _ =>
        -- State variables — Phase 2
        pure ()
      | _ => pure ()  -- Skip unsupported members

    return (procedures, types)
  | _ => throw (.internalError "Expected ContractDefinition")

/-! ## Top-Level Translation -/

/-- Translate a Solidity SourceUnit (top-level AST) to a Laurel Program. -/
def solidityToLaurel (cmd : Solidity.Command SourceRange)
    : Except TranslationError Laurel.Program := do
  match cmd with
  | .SourceUnit _ nodesSeq => do
    let mut allProcedures : List Procedure := []
    let mut allTypes : List TypeDefinition := []

    for node in nodesSeq.val do
      match node with
      | .ContractDefinition _ _ _ _ => do
        let (procs, types) ← translateContract node
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
