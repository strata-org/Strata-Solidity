/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

import StrataSolidity.SolTranslator.Types
import StrataSolidity.SolTranslator.SpecParser

namespace Strata.Solidity
open Laurel

/-! ## Expression Translation -/

/-- Check if a VariableDeclarationStatement declares a storage reference. -/
def isStorageRefDecl (n : Solidity.node SourceRange) : Option (String × Solidity.opt_node SourceRange) :=
  match n with
  | .VariableDeclarationStatement _ declsSeq initOpt =>
    match declsSeq.val.toList with
    | [declOpt] =>
      match declOpt with
      | .some_node _ (.VariableDeclaration _ nameAnn _ _ _ _ _ _ storageLocAnn _ _) =>
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
    | [.some_node _ (.VariableDeclaration _ _ typeNameOpt _ _ _ _ _ _ _ _)] =>
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
      | .some_node _ (.Literal _ _ _ _) => true
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
  | [idx] => return mkStmtExprMd (mkCall "update" [rootExpr, idx, val])
  | idx :: rest =>
    let inner := mkStmtExprMd (mkCall "select" [rootExpr, idx])
    let innerUpdate ← buildNestedUpdate inner rest val
    return mkStmtExprMd (mkCall "update" [rootExpr, idx, innerUpdate])


/-- Whether evaluating a translated expression does more than compute a
    value: anything but literals, variables, conditionals, map reads and
    operators without a precondition (so `k++`, an assignment, a call, a
    division). Laurel lifts such parts out of the expression, evaluating
    them before it. -/
def hasEffects (e : StmtExprMd) : Bool :=
  anyStmtExpr (fun e => match e.val with
    | .LiteralInt _ | .LiteralBool _ | .LiteralString _ | .Var (.Local _) | .Var (.Field ..)
    | .IfThenElse .. => false
    | .StaticCall callee _ _ =>
      match asPrimOp? e.val with
      | some (op, _) => (op matches .Div | .Mod | .DivT | .ModT)
      | none => !["select", "mapConst"].contains callee.text
    | _ => true) e

/-- A local `x` declared with the value `e`. -/
def declareLocal (x : String) (e : StmtExprMd) : StmtExprMd :=
  mkStmtExprMd (.Assign [{ val := .Declare { name := x, type := none }, source := .unknown }] e)

/-- Evaluate expressions once each, in order: if any of them has effects,
    bind every one to a fresh local `<pre>_<i>` (declarations to run first)
    and use the locals instead; otherwise use the expressions as they are. -/
def bindInOrder (pre : String) (es : List StmtExprMd) : List StmtExprMd × List StmtExprMd :=
  if !es.any hasEffects then ([], es) else
    let named := es.zipIdx.map fun (e, i) => (s!"{pre}_{i}", e)
    (named.map fun (x, e) => declareLocal x e,
     named.map fun (x, _) => mkStmtExprMd (mkIdentifier x))

/-- An internal call `f(args)` to a function with signature `sig`.

    The arguments follow the callee's input order exactly (see
    `translateFunction`): `self` and the pre-state `<f>_in` of each scalar
    state variable (for a non-pure callee in a contract with scalar state),
    `msg_sender` and `msg_value` (non-pure), the current value of each
    mapping and array state variable with its `_length` (non-pure), then the
    user arguments, each memory-array argument followed by its length.

    A mutating callee (neither pure nor view) also returns the post-state of
    every mapping and array state variable after its declared return values.
    Those outputs are bound back to the caller's variables by a
    multi-target assignment inside a block expression, which yields the
    single declared return value, if any; Laurel lifts it out of the
    surrounding expression. Dropping them would make the caller reason
    about stale mappings after the call. -/
def translateInternalCall (ctx : TransCtx) (sr : SourceRange) (callee : String) (sig : FnSig)
    (argNodes : List (Solidity.node SourceRange)) (args : List StmtExprMd)
    : Except TranslationError StmtExprMd := do
  let ident (n : String) := mkStmtExprMd (mkIdentifier n)
  -- User arguments, each memory-array argument followed by its length.
  let mut userArgs : List StmtExprMd := []
  for ((node, arg), i) in (argNodes.zip args).zipIdx do
    userArgs := userArgs ++ [arg]
    if sig.memArrayParams.getD i false then
      match node with
      | .Identifier _ nameAnn =>
        if ctx.memoryArrayParams.contains nameAnn.val || ctx.arrayStateVars.contains nameAnn.val then
          userArgs := userArgs ++ [ident s!"{nameAnn.val}_length"]
        else throw (.unsupported
          s!"array argument `{nameAnn.val}` to `{callee}` has no known length")
      | _ => throw (.unsupported s!"array argument to `{callee}` must be a variable")
  if sig.isPure then return mkStmtExprMd (mkCall callee userArgs)
  let scalars := ctx.stateVarNames.filter (!ctx.mappingStateVars.contains ·)
  let mut implicitArgs : List StmtExprMd := []
  if !scalars.isEmpty then
    if !ctx.hasSelfParam then
      throw (.unsupported s!"internal call to `{callee}` from a function without contract state access (e.g. the constructor)")
    implicitArgs := implicitArgs ++ [ident "self"] ++
      scalars.map fun n => mkStmtExprMd (mkFieldSelect (ident "self") n)
  implicitArgs := implicitArgs ++ [ident "msg_sender", ident "msg_value"]
  let stateVars := ctx.mappingStateVars.flatMap fun m =>
    if ctx.arrayStateVars.contains m then [m, s!"{m}_length"] else [m]
  implicitArgs := implicitArgs ++ stateVars.map ident
  let call := withSourceRange ctx sr (mkStmtExprMd (mkCall callee (implicitArgs ++ userArgs)))
  if sig.isView || stateVars.isEmpty then return call
  -- Mutating callee: bind the declared returns to fresh locals and the
  -- state outputs to the caller's state variables.
  let temps := sig.returnTypes.zipIdx.map fun (ty, i) => (s!"__ret{sr.start.byteIdx}_{i}", ty)
  let targets : List (AstNode Variable) :=
    temps.map (fun (n, ty) => { val := .Declare { name := n, type := some ty }, source := .unknown }) ++
    stateVars.map fun n => { val := .Local (mkIdent n), source := .unknown }
  let assign := withSourceRange ctx sr (mkStmtExprMd (.Assign targets call))
  match temps with
  | [(n, _)] => return mkStmtExprMd (.Block [assign, ident n] none)
  | _ => return mkStmtExprMd (.Block [assign] none)

/-- What an inline-assembly block may do, read from solc's Yul AST (the
    `InlineAssembly` payload). -/
structure YulSummary where
  /-- Names the block assigns (`x := …`; the variable of `p.slot := …`).
      Some are Yul locals. -/
  assigned : List String
  /-- Whether it writes memory (`mstore`, a copy, a call's output area). -/
  writesMemory : Bool
  /-- Whether it may write this contract's storage: `sstore`, or a call or
      creation that can run code writing it. -/
  writesStorage : Bool
  /-- Whether it may end the function (`return`, `stop`, `selfdestruct`). -/
  exits : Bool

/-- `yulSummary?` for a block whose Yul AST is unknown: it may do anything
    to the given variables. -/
def YulSummary.any (vars : List String) : YulSummary :=
  { assigned := vars, writesMemory := true, writesStorage := true, exits := true }

/-- The summary of a Yul AST, or `none` if the payload is not one. -/
partial def yulSummary? (payload : String) : Option YulSummary :=
  match Lean.Json.parse payload with
  | .ok j =>
    if j.getObjValD "nodeType" == .str "YulBlock" then
      let (assigned, called) := collect j
      let calls (fs : List String) := called.any fs.contains
      some { assigned
             writesMemory := calls ["mstore", "mstore8", "mcopy", "calldatacopy", "codecopy",
               "extcodecopy", "returndatacopy", "datacopy", "call", "callcode", "delegatecall",
               "staticcall"]
             writesStorage := calls ["sstore", "call", "callcode", "delegatecall", "create", "create2"]
             exits := calls ["return", "stop", "selfdestruct"] }
    else none
  | .error _ => none
where
  /-- Assigned names and called functions. -/
  collect : Lean.Json → List String × List String
    | .obj kvs =>
      let kvs := kvs.toList
      let name (v : Lean.Json) : Option String := match v.getObjVal? "name" with
        | .ok (.str n) => (n.splitOn ".").head?
        | _ => none
      let assigned := match kvs.lookup "nodeType", kvs.lookup "variableNames" with
        | some (.str "YulAssignment"), some (.arr vs) => vs.toList.filterMap name
        | _, _ => []
      let called := match kvs.lookup "nodeType", kvs.lookup "functionName" with
        | some (.str "YulFunctionCall"), some f => (name f).toList
        | _, _ => []
      kvs.foldl (fun (a, c) (_, v) => let (a', c') := collect v; (a ++ a', c ++ c'))
        (assigned, called)
    | .arr xs => xs.foldl (fun (a, c) x => let (a', c') := collect x; (a ++ a', c ++ c')) ([], [])
    | _ => ([], [])

/-- The Solidity variables in scope that inline assembly can assign:
    locals, parameters and named returns, but not the variables carrying
    mapping and array state, which Yul cannot name (and which are inputs
    of `view` functions). -/
def assemblyAssignable (ctx : TransCtx) : List String :=
  let stateNames := ctx.mappingStateVars ++ ctx.arrayStateVars.map (· ++ "_length")
  ctx.localNames.filter (!stateNames.contains ·) |>.eraseDups

/-- The model of an inline-assembly block with summary `s`. Yul is not
    interpreted: whatever the block may write is unknown afterwards, and
    it may end the function there.
    - The Solidity variables it assigns get fresh values, a memory array
      with its length; so does every variable in memory if it writes memory.
    - If it may write storage, so does all of the contract's state, where
      solc lets assembly write it (not in `view` and `pure` functions).
    - If it may end the function, it does so on some paths, with unknown
      return values.
    Fresh values are nondeterministic holes: a deterministic hole is a
    function of the procedure's inputs, so a block in a loop would produce
    the same value at every iteration. -/
def assemblyModel (ctx : TransCtx) (s : YulSummary) : Except TranslationError StmtExprMd := do
  let fresh := mkStmtExprMd (.Hole (deterministic := false))
  let assign (target : StmtExprMd) := mkStmtExprMd (.Assign [toAssignTarget target] fresh)
  let ident (n : String) := mkStmtExprMd (mkIdentifier n)
  if let some p := s.assigned.find? fun n => ctx.storageAliases.any (·.1 == n) then
    throw (.unsupported s!"inline assembly that assigns the storage reference `{p}`")
  if s.writesMemory then
    if let some (v, _) := ctx.memoryVars.find? (·.2.val matches .UserDefined _) then
      throw (.unsupported s!"inline assembly that writes memory while the memory struct `{v}` is in scope")
  if s.exits && ctx.isConstructor then
    throw (.unsupported "inline assembly that may end the constructor")
  let memory := if s.writesMemory then ctx.memoryVars.map (·.1) else []
  let vars := (assemblyAssignable ctx).filter fun n => s.assigned.contains n || memory.contains n
  let vars := vars.flatMap fun n =>
    if ctx.memoryArrayParams.contains n then [n, s!"{n}_length"] else [n]
  let state := if !(s.writesStorage && ctx.mayWriteState) then [] else
    ctx.stateVarNames.flatMap fun n =>
      if ctx.arrayStateVars.contains n then [n, s!"{n}_length"] else [n]
  -- Scalar state is a field of `self`, except in constructors, where it
  -- is an output variable like mapping state.
  let (fields, stateVars) := state.partition fun n =>
    ctx.hasSelfParam && ctx.stateVarNames.contains n && !ctx.mappingStateVars.contains n
  let havocs := (vars ++ stateVars).eraseDups.map (assign ∘ ident) ++
    fields.map fun n => assign (mkStmtExprMd (mkFieldSelect (ident "self") n))
  let exit := if !s.exits then [] else
    [mkStmtExprMd (.IfThenElse fresh
      (mkStmtExprMd (.Block (ctx.returnNames.map (assign ∘ ident) ++ [mkStmtExprMd (.Return none)]) none))
      none)]
  return mkStmtExprMd (.Block (havocs ++ exit) none)

/-- The loop condition and the statements to run at the top of each
    iteration. Laurel lifts the effects of a condition (a call, `k++`, an
    assignment, a division's check; see `hasEffects`) out of the loop,
    evaluating them once before the first iteration, so a loop with such a
    condition is translated as `while (true) { if (!cond) break; … }`,
    which evaluates the condition at every iteration as Solidity does. -/
def loopHead (cond : StmtExprMd) (breakLbl : String)
    : StmtExprMd × List StmtExprMd :=
  if hasEffects cond then
    (mkStmtExprMd (.LiteralBool true),
     [mkStmtExprMd (.IfThenElse (mkStmtExprMd (mkPrimOp .Not [cond]))
        (mkStmtExprMd (.Exit breakLbl)) none)])
  else (cond, [])

/-- Source range of an expression node (`none` for other node kinds). -/
def exprRange : Solidity.node SourceRange → SourceRange
  | .BinaryOperation sr .. | .UnaryOperation sr .. | .FunctionCall sr .. | .IndexAccess sr ..
  | .MemberAccess sr .. | .Conditional sr .. | .Assignment sr .. | .TupleExpression sr ..
  | .FunctionCallOptions sr .. | .Identifier sr .. | .Literal sr .. => sr
  | _ => .none

mutual

/-- Translate a Solidity DDM node (expression context) to Laurel StmtExpr.
    The result carries the node's source range unless the translation chose
    one itself: Laurel locates the checks it generates for an expression
    (callee preconditions at a call, `divisor is non-zero` at a division)
    at that expression's node. -/
partial def translateExpr (ctx : TransCtx) (n : Solidity.node SourceRange)
    : Except TranslationError StmtExprMd := do
  let e ← translateExprAt ctx n
  if e.source == .unknown then pure (withSourceRange ctx (exprRange n) e) else pure e

/-- `translateExpr` without attaching the node's source range. -/
partial def translateExprAt (ctx : TransCtx) (n : Solidity.node SourceRange)
    : Except TranslationError StmtExprMd := do
  match n with
  | .Identifier _ nameAnn =>
    -- Local variables and parameters shadow state variables
    if ctx.localNames.contains nameAnn.val then
      return mkStmtExprMd (mkIdentifier nameAnn.val)
    else if let some valExpr := ctx.constantDefs.lookup nameAnn.val then
      -- Constant state variable: substitute compile-time value
      return valExpr
    else if ctx.mappingStateVars.contains nameAnn.val then
      -- Mapping state vars are explicit parameters, not heap fields
      return mkStmtExprMd (mkIdentifier nameAnn.val)
    else if ctx.stateVarNames.contains nameAnn.val then
      return mkStmtExprMd (mkFieldSelect (mkStmtExprMd (mkIdentifier "self")) nameAnn.val)
    else
      return mkStmtExprMd (mkIdentifier nameAnn.val)

  | .Literal _ valueAnn kindAnn subAnn =>
    match kindAnn.val with
    | "number" =>
      let v := valueAnn.val
      let parsed := if v.startsWith "0x" || v.startsWith "0X" then
        -- Hex literal: parse manually
        let hexStr := v.drop 2
        hexStr.foldl (fun acc c =>
          acc.bind fun n =>
            let d := if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat)
              else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
              else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
              else none
            d.map (n * 16 + ·)) (some 0) |>.map Int.ofNat
      else v.toInt?
      match parsed with
      | some i =>
        -- Apply subdenomination unit multiplier (Solidity ether/time units).
        -- e.g. `1 ether` == 10^18 wei, `1 days` == 86400 seconds.
        let factor : Int := match subAnn.val with
          | "wei"     => 1
          | "gwei"    => 1000000000
          | "ether"   => 1000000000000000000
          | "seconds" => 1
          | "minutes" => 60
          | "hours"   => 3600
          | "days"    => 86400
          | "weeks"   => 604800
          | _         => 1
        return mkStmtExprMd (.LiteralInt (i * factor))
      | none => throw (.typeError s!"Invalid number literal: {v}")
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
      -- Short-circuit: the right operand is evaluated only if needed, so
      -- its effects (calls, checks) happen only on those paths.
      | "&&" => .ok Operation.AndThen
      | "||" => .ok Operation.OrElse
      | "&" => return mkStmtExprMd (mkCall "bit_and" [l, r])
      | "|" => return mkStmtExprMd (mkCall "bit_or" [l, r])
      | "^" => return mkStmtExprMd (mkCall "bit_xor" [l, r])
      | "<<" => return mkStmtExprMd (mkCall "bit_shl" [l, r])
      | ">>" => return mkStmtExprMd (mkCall "bit_shr" [l, r])
      | o => throw (.unsupported s!"Binary operator: {o}")
    return mkStmtExprMd (mkPrimOp op [l, r])

  | .UnaryOperation _ sub opAnn prefixAnn => do
    -- Handle delete before translating sub, since mapping delete needs raw AST
    if opAnn.val == "delete" then
      let zero := mkStmtExprMd (.LiteralInt 0)
      match collectIndexChain sub with
      | some (rootNode, indices) => do
        let rootExpr ← translateExpr ctx rootNode
        let idxExprs ← indices.mapM (translateExpr ctx)
        let updateExpr ← buildNestedUpdate rootExpr idxExprs zero
        return mkStmtExprMd (.Assign [toAssignTarget rootExpr] updateExpr)
      | none =>
        let subExpr ← translateExpr ctx sub
        return mkStmtExprMd (.Assign [toAssignTarget subExpr] zero)
    -- `++`/`--` on a mapping or array element: write back through
    -- `update`. Each index is evaluated once (`m[k++]++`), and the
    -- expression yields the old element (postfix) or the new one (prefix).
    if opAnn.val == "++" || opAnn.val == "--" then
      if let some (rootNode, indices) := collectIndexChain sub then
        let rootExpr ← translateExpr ctx rootNode
        let idxExprs ← indices.mapM (translateExpr ctx)
        let off := (exprRange n).start.byteIdx
        let (binds, keys) := bindInOrder s!"__k{off}" idxExprs
        let read := keys.foldl (fun acc k => mkStmtExprMd (mkCall "select" [acc, k])) rootExpr
        let old := s!"__old{off}"
        let oldVar := mkStmtExprMd (mkIdentifier old)
        let newVal := mkStmtExprMd (mkPrimOp (if opAnn.val == "++" then .Add else .Sub)
          [oldVar, mkStmtExprMd (.LiteralInt 1)])
        let updateExpr ← buildNestedUpdate rootExpr keys newVal
        return mkStmtExprMd (.Block (binds ++ [
          declareLocal old read,
          mkStmtExprMd (.Assign [toAssignTarget rootExpr] updateExpr),
          if prefixAnn.val == "true" then newVal else oldVar]) none)
    let subExpr ← translateExpr ctx sub
    -- Laurel's native `++`/`--` (on a variable or field): prefix yields the
    -- new value and postfix the old one, as in Solidity (`x = i++`).
    let incrDecr (mode : IncrDecrMode) (op : IncrDecrOp) : StmtExprMd :=
      mkStmtExprMd (.IncrDecr mode op (toAssignTarget subExpr))
    if prefixAnn.val == "true" then
      match opAnn.val with
      | "!" => return mkStmtExprMd (mkPrimOp .Not [subExpr])
      | "-" => return mkStmtExprMd (mkPrimOp .Neg [subExpr])
      | "~" => return mkStmtExprMd (mkCall "bit_not" [subExpr])
      | "++" => return incrDecr .Pre .Incr
      | "--" => return incrDecr .Pre .Decr
      | o => throw (.unsupported s!"Prefix unary operator: {o}")
    else
      match opAnn.val with
      | "++" => return incrDecr .Post .Incr
      | "--" => return incrDecr .Post .Decr
      | o => throw (.unsupported s!"Postfix unary operator: {o}")

  -- `new T(args)` parses as FunctionCall(NewExpression(T), args). Contract
  -- creation is an opaque external effect and dynamic memory arrays
  -- (`new uint[](n)`) yield a fresh unconstrained value. Model as a Hole.
  -- Must precede the general FunctionCall arm (matched top-to-bottom).
  | .FunctionCall _ (.NewExpression _ _) _ _ _ =>
    return mkStmtExprMd .Hole

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
      return mkStmtExprMd (mkCall (s!"{structName}_constructor") orderedArgs)
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
        -- require(cond), require(cond, msg), or require(cond, CustomError(args)) → assume(cond)
        -- The `cond :: _` pattern handles all arities (1, 2, 3+): extra arguments
        -- (string messages, custom error constructors) are runtime diagnostics only
        -- and are ignored for verification purposes.
        -- No source metadata: assume nodes don't generate VCs
        match args with
        | cond :: _ => return mkStmtExprMd (mkAssume cond)
        | [] => throw (.typeError "require() needs at least one argument")
      | "assert" =>
        match args with
        | [cond] => return mkStmtExprMdAnn ctx sr (mkAssert cond)
        | _ => throw (.typeError "assert() expects exactly one argument")
      | "keccak256" | "sha256" =>
        return mkStmtExprMd (mkCall nameAnn.val args)
      | "gasleft" =>
        -- A fresh uint256 at every call (an opaque procedure, see
        -- `envProcedures`).
        return mkStmtExprMd (mkCall "gasleft" [])
      | "selfdestruct" =>
        -- selfdestruct(addr) → deprecated, model as no-op
        return mkStmtExprMd .Hole
      | funcName =>
        -- Internal call: prefix with contract name to match procedure declaration
        let qualifiedName := s!"{ctx.contractName}_{funcName}"
        match ctx.functionSigs.lookup funcName with
        | none => return mkStmtExprMd (mkCall qualifiedName args)
        | some sig =>
          -- Named arguments (`f({to: a, amount: x})`) bind by name: put
          -- them in declaration order.
          let names := namesSeq.val.toList.map (·.val)
          let (argNodes, args) ← if names.isEmpty then pure (argsSeq.val.toList, args) else do
            let named := names.zip (argsSeq.val.toList.zip args)
            let ordered ← sig.paramNames.mapM fun p => match named.lookup p with
              | some a => pure a
              | none => throw (.typeError s!"call to `{funcName}` has no argument named `{p}`")
            pure (ordered.map (·.1), ordered.map (·.2))
          translateInternalCall ctx sr qualifiedName sig argNodes args
    | .MemberAccess _ baseNode memberAnn =>
      -- Handle array.push(val) on array state variables
      -- User-defined value type wrap/unwrap (`Wei.wrap(x)`, `Wei.unwrap(w)`)
      -- are pure identity on the underlying representation (issue #13).
      -- Guarded on the base being a KNOWN UDVT name: a plain method that
      -- happens to be called `wrap`/`unwrap` (e.g. `wstETH.wrap(amount)`,
      -- which converts at a rate) must NOT be modeled as identity — it falls
      -- through to the general uninterpreted-call path below.
      let baseIsUdvt := match baseNode with
        | .Identifier _ baseNameAnn => ctx.udvtNames.contains baseNameAnn.val
        | _ => false
      if (memberAnn.val == "wrap" || memberAnn.val == "unwrap") && baseIsUdvt then do
        let args ← argsSeq.val.toList.mapM (translateExpr ctx)
        match args with
        | [x] => return x
        | _ => throw (.typeError s!"{memberAnn.val}() expects exactly one argument")
      else if memberAnn.val == "push" then do
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
            let arrId := mkStmtExprMd (mkIdentifier name)
            let lenId := mkStmtExprMd (mkIdentifier s!"{name}_length")
            let store := mkStmtExprMd (.Assign [toAssignTarget arrId]
              (mkStmtExprMd (mkCall "update" [arrId, lenId, val])))
            let one := mkStmtExprMd (.LiteralInt 1)
            let incr := mkStmtExprMd (.Assign [toAssignTarget lenId]
              (mkStmtExprMd (mkPrimOp .Add [lenId, one])))
            return mkStmtExprMd (.Block [store, incr] none)
          | [] => throw (.unsupported "push() with no arguments (returns storage reference)")
          | _ => throw (.typeError "push() expects at most one argument")
        | none =>
          -- Fallback: generic push (not on a known array state var)
          let base ← translateExpr ctx baseNode
          match args with
          | [val] => return mkStmtExprMd (mkCall "array_push" [base, val])
          | [] => throw (.unsupported "push() with no arguments (returns storage reference)")
          | _ => throw (.typeError "push() expects at most one argument")
      else if memberAnn.val == "transfer" then do
        let args ← argsSeq.val.toList.mapM (translateExpr ctx)
        -- payable(addr).transfer(amount) → no-op for verification; a
        -- contract's `transfer(to, amount)` (ERC-20) → unknown result
        if args.length == 1 then return mkStmtExprMd (.Block [] none)
        else return mkStmtExprMd .Hole
      else if memberAnn.val == "send" then do
        -- payable(addr).send(amount) → a fresh bool: whether it succeeded
        let _args ← argsSeq.val.toList.mapM (translateExpr ctx)
        return mkStmtExprMd (mkCall "send_result" [])
      else if memberAnn.val == "call" || memberAnn.val == "delegatecall"
              || memberAnn.val == "staticcall" then do
        -- addr.call/delegatecall/staticcall → nondeterministic (modeled as Hole)
        let _args ← argsSeq.val.toList.mapM (translateExpr ctx)
        return mkStmtExprMd .Hole
      else do
        -- abi.encode*, abi.decode → uninterpreted StaticCall "abi_<method>"
        match baseNode with
        | .Identifier _ baseNameAnn =>
          if baseNameAnn.val == "abi" then do
            let args ← argsSeq.val.toList.mapM (translateExpr ctx)
            let suffix := if args.length > 1 then s!"{args.length}" else ""
            return mkStmtExprMd (mkCall s!"abi_{memberAnn.val}{suffix}" args)
        | _ => pure ()
        -- General method call: obj.method(args) → StaticCall "method" (obj :: args)
        let base ← translateExpr ctx baseNode
        let args ← argsSeq.val.toList.mapM (translateExpr ctx)
        return mkStmtExprMd (mkCall memberAnn.val (base :: args))
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
          return mkStmtExprMd (mkIdentifier "msg_sender")
        else if memberAnn.val == "value" then
          return mkStmtExprMd (mkIdentifier "msg_value")
        else if let some (c, _) := envConstants.find? (·.2.1 == s!"msg.{memberAnn.val}") then
          -- msg.data, msg.sig: constants of the transaction
          return mkStmtExprMd (mkCall c [])
        else
          throw (.unsupported s!"msg.{memberAnn.val}")
      else if baseNameAnn.val == "block" || baseNameAnn.val == "tx" then
        -- block.timestamp, tx.origin, …: constants of the transaction
        let solName := s!"{baseNameAnn.val}.{memberAnn.val}"
        match envConstants.find? (·.2.1 == solName) with
        | some (c, _) => return mkStmtExprMd (mkCall c [])
        | none => throw (.unsupported solName)
      else pure ()
      -- Enum member access: Status.Active → integer literal for position
      match ctx.enumDefs.lookup baseNameAnn.val with
      | some members =>
        match List.findIndex? (· == memberAnn.val) members with
        | some i => return mkStmtExprMd (.LiteralInt i)
        | none => throw (.typeError s!"Unknown enum member '{memberAnn.val}' in '{baseNameAnn.val}'")
      | none => pure ()
      -- Storage alias field access: sender.field → Identifier "sender__field"
      match ctx.storageAliases.lookup baseNameAnn.val with
      | some _ => return mkStmtExprMd (mkIdentifier s!"{baseNameAnn.val}__{memberAnn.val}")
      | none => pure ()
      -- Array .length on state vars or memory array params → Identifier "name_length"
      if memberAnn.val == "length" then
        let name := baseNameAnn.val
        if ctx.arrayStateVars.contains name ||
           ctx.memoryArrayParams.contains name then
          return mkStmtExprMd (mkIdentifier s!"{name}_length")
    | .FunctionCall _ (.Identifier _ typeIdAnn) argsSeq _ _ =>
      -- type(T).min / type(T).max → integer literal constant
      if typeIdAnn.val == "type" then
        match argsSeq.val.toList with
        | [.ElementaryTypeNameExpression _ typeNameAnn] =>
          if memberAnn.val == "min" || memberAnn.val == "max" then
            match SpecParser.typeMinMax typeNameAnn.val memberAnn.val with
            | some v => return mkStmtExprMd (.LiteralInt v)
            | none => throw (.unsupported s!"type({typeNameAnn.val}).{memberAnn.val}")
          else pure ()
        | _ => pure ()
      else pure ()
    | .FunctionCall _ (.ElementaryTypeNameExpression _ typeNameAnn) argsSeq _ _ =>
      -- address(x).balance → address_balance(x), address(this).balance →
      -- this_balance(): a fresh uint256 at every read (balances change
      -- with transfers, which are not modelled)
      if typeNameAnn.val == "address" || typeNameAnn.val == "address payable" then
        if memberAnn.val == "balance" then
          match argsSeq.val.toList with
          | [.Identifier _ argAnn] =>
            if argAnn.val == "this" then
              return mkStmtExprMd (mkCall "this_balance" [])
            else do
              let addrExpr ← translateExpr ctx (.Identifier default argAnn)
              return mkStmtExprMd (mkCall "address_balance" [addrExpr])
          | [arg] => do
            let addrExpr ← translateExpr ctx arg
            return mkStmtExprMd (mkCall "address_balance" [addrExpr])
          | _ => pure ()
        else if memberAnn.val == "code" || memberAnn.val == "codehash" then
          match argsSeq.val.toList with
          | [arg] => do
            let addrExpr ← translateExpr ctx arg
            return mkStmtExprMd (mkCall s!"address_{memberAnn.val}" [addrExpr])
          | _ => pure ()
      else pure ()
    | _ => pure ()
    let obj ← translateExpr ctx exprNode
    if memberAnn.val == "length" then
      return mkStmtExprMd (mkCall "array_length" [obj])
    else if memberAnn.val == "code" || memberAnn.val == "codehash" then
      return mkStmtExprMd (mkCall s!"address_{memberAnn.val}" [obj])
    else
      return mkStmtExprMd (mkFieldSelect obj memberAnn.val)

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
      return mkStmtExprMd (mkCall "select" [base, idxExpr])
    | .missing_node _ =>
      throw (.unsupported "IndexAccess without index")

  | .Conditional _ cond trueExpr falseExpr => do
    let c ← translateExpr ctx cond
    let t ← translateExpr ctx trueExpr
    let f ← translateExpr ctx falseExpr
    return mkStmtExprMd (.IfThenElse c t (some f))

  | .TupleExpression _ componentsSeq => do
    -- Simple case: parenthesized single expression (expr) → translate inner
    match componentsSeq.val.toList with
    | [inner] => translateExpr ctx inner
    | _ =>
      -- A multi-component tuple as a value (`return (a, b)`, `(a, b) = …`)
      -- is not supported. It must not become `assume false`, which would
      -- silently make every later obligation on the path hold.
      throw (.unsupported "tuple expressions with several components are not supported here")

  | .Assignment _ lhs rhs opAnn => do
    let rhsExpr ← translateExpr ctx rhs
    -- Solidity evaluates the right-hand side first, then the indices, then
    -- reads the target (for `op=`). If any of them has effects (a call
    -- that writes the same mapping, `k++`), they are bound to locals in
    -- that order, so the write sees the state they leave.
    let off := (exprRange n).start.byteIdx
    let rhsVar := s!"__rhs{off}"
    -- Handle IndexAccess on LHS: map/array writes via select/update
    match collectIndexChain lhs with
    | some (rootNode, indices) => do
      let rootExpr ← translateExpr ctx rootNode
      let idxExprs ← indices.mapM (translateExpr ctx)
      let inPlace := !(rhsExpr :: idxExprs).any hasEffects
      let (binds, rhsExpr, idxExprs) := if inPlace then ([], rhsExpr, idxExprs) else
        let (idxBinds, keys) := bindInOrder s!"__k{off}" idxExprs
        (declareLocal rhsVar rhsExpr :: idxBinds, mkStmtExprMd (mkIdentifier rhsVar), keys)
      -- Build the read expression: select(select(root, k1), k2) ...
      let readExpr := idxExprs.foldl (fun acc idx =>
        mkStmtExprMd (mkCall "select" [acc, idx])) rootExpr
      -- Compute the value to store
      let rhs' ← match opAnn.val with
        | "=" => pure rhsExpr
        | "+=" => pure (mkStmtExprMd (mkPrimOp .Add [readExpr, rhsExpr]))
        | "-=" => pure (mkStmtExprMd (mkPrimOp .Sub [readExpr, rhsExpr]))
        | "*=" => pure (mkStmtExprMd (mkPrimOp .Mul [readExpr, rhsExpr]))
        | "/=" => pure (mkStmtExprMd (mkPrimOp .Div [readExpr, rhsExpr]))
        | "%=" => pure (mkStmtExprMd (mkPrimOp .Mod [readExpr, rhsExpr]))
        | "&=" => pure (mkStmtExprMd (mkCall "bit_and" [readExpr, rhsExpr]))
        | "|=" => pure (mkStmtExprMd (mkCall "bit_or" [readExpr, rhsExpr]))
        | "^=" => pure (mkStmtExprMd (mkCall "bit_xor" [readExpr, rhsExpr]))
        | "<<=" => pure (mkStmtExprMd (mkCall "bit_shl" [readExpr, rhsExpr]))
        | ">>=" => pure (mkStmtExprMd (mkCall "bit_shr" [readExpr, rhsExpr]))
        | o => throw (.unsupported s!"Assignment operator: {o}")
      -- Build nested update: for m[k1][k2] = v, produce
      --   Assign [root] (update(root, k1, update(select(root, k1), k2, v)))
      let updateExpr ← buildNestedUpdate rootExpr idxExprs rhs'
      let assign := mkStmtExprMd (.Assign [toAssignTarget rootExpr] updateExpr)
      if binds.isEmpty then return assign
      return mkStmtExprMd (.Block (binds ++ [assign]) none)
    | none =>
    let lhsExpr ← translateExpr ctx lhs
    -- `x op= f()`: the target is read after the right-hand side runs.
    let (binds, rhsExpr) := if opAnn.val == "=" || !hasEffects rhsExpr then ([], rhsExpr) else
      ([declareLocal rhsVar rhsExpr], mkStmtExprMd (mkIdentifier rhsVar))
    let rhs' ← match opAnn.val with
      | "=" => pure rhsExpr
      | "+=" => pure (mkStmtExprMd (mkPrimOp .Add [lhsExpr, rhsExpr]))
      | "-=" => pure (mkStmtExprMd (mkPrimOp .Sub [lhsExpr, rhsExpr]))
      | "*=" => pure (mkStmtExprMd (mkPrimOp .Mul [lhsExpr, rhsExpr]))
      | "/=" => pure (mkStmtExprMd (mkPrimOp .Div [lhsExpr, rhsExpr]))
      | "%=" => pure (mkStmtExprMd (mkPrimOp .Mod [lhsExpr, rhsExpr]))
      | "&=" => pure (mkStmtExprMd (mkCall "bit_and" [lhsExpr, rhsExpr]))
      | "|=" => pure (mkStmtExprMd (mkCall "bit_or" [lhsExpr, rhsExpr]))
      | "^=" => pure (mkStmtExprMd (mkCall "bit_xor" [lhsExpr, rhsExpr]))
      | "<<=" => pure (mkStmtExprMd (mkCall "bit_shl" [lhsExpr, rhsExpr]))
      | ">>=" => pure (mkStmtExprMd (mkCall "bit_shr" [lhsExpr, rhsExpr]))
      | o => throw (.unsupported s!"Assignment operator: {o}")
    let assign := mkStmtExprMd (.Assign [toAssignTarget lhsExpr] rhs')
    if binds.isEmpty then return assign
    return mkStmtExprMd (.Block (binds ++ [assign]) none)

  -- Call with {value:, gas:} options: the options don't affect verification
  -- semantics (ETH transfer is external/opaque). Translate the wrapped call.
  | .FunctionCallOptions _ inner _ _ => translateExpr ctx inner

  -- A bare NewExpression operand (no call args) — also opaque.
  | .NewExpression _ _ =>
    return mkStmtExprMd .Hole

  -- Static array literal `[a, b, c]`. A faithful model requires the memory-
  -- array length-tracking representation the translator uses for other arrays;
  -- the simple fresh-map encoding conflicts with it. Until that lands, reject
  -- explicitly (sound: a clean error, never a silent vacuous pass).
  | .InlineArrayExpression _ _ =>
    throw (.unsupported "inline array literal [a, b, c] (needs memory-array length tracking)")

  -- Calldata/bytes slice `x[start:end]`. Opaque slice — fresh unconstrained
  -- value (sound over-approximation).
  | .IndexRangeAccess _ _ _ _ =>
    return mkStmtExprMd .Hole

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
        let fieldInit := mkStmtExprMd (mkFieldSelect initExpr fieldName)
        mkStmtExprMd (mkLocalVar s!"{aliasName}__{fieldName}" (mkHighTypeMd fieldType) (some fieldInit))
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
          | [.some_node _ (.VariableDeclaration _ nameAnn typeOpt _ _ _ _ _ storageLocAnn _ _)] =>
            let ctx := { ctx with localNames := ctx.localNames ++ [nameAnn.val] }
            match storageLocAnn.val, typeOpt with
            | "memory", .some_type_name _ tn =>
              { ctx with memoryVars := ctx.memoryVars ++ [(nameAnn.val, (translateTypeNode ctx tn).highType)] }
            | _, _ => ctx
          | _ => ctx
        | _ => ctx
      let s ← translateStmt ctx' stmt
      let rest' ← translateBlockStmts ctx' rest
      return s :: rest'

/-- Get loop invariants from context and translate the loop body.
    Returns (invariantExprs, translatedBody). -/
partial def extractAndTranslateLoopInvariants (ctx : TransCtx) (body : Solidity.node SourceRange)
    : Except TranslationError (List StmtExprMd × StmtExprMd) := do
  let b ← translateStmt ctx body
  pure (ctx.loopInvariantExprs, b)

/-- Translate a Solidity DDM node (statement context) to Laurel StmtExpr. -/
partial def translateStmt (ctx : TransCtx) (n : Solidity.node SourceRange)
    : Except TranslationError StmtExprMd := do
  match n with
  | .Block _ stmtsSeq => do
    let stmts ← translateBlockStmts ctx stmtsSeq.val.toList
    return mkStmtExprMd (.Block stmts none)

  -- Unchecked blocks: in Solidity, `unchecked { }` disables overflow/underflow
  -- revert checks for arithmetic. Currently our arithmetic (PrimitiveOp.Add/Sub/Mul)
  -- maps to unbounded integer operations with no overflow checks, so the semantic
  -- difference is a no-op. When bounded arithmetic / overflow checks are added,
  -- the `isInsideUnchecked` flag should be checked to skip them.
  | .UncheckedBlock _ stmtsSeq => do
    let uncheckedCtx := { ctx with isInsideUnchecked := true }
    let stmts ← translateBlockStmts uncheckedCtx stmtsSeq.val.toList
    return mkStmtExprMd (.Block stmts none)

  -- Inline assembly: see `assemblyModel`. Without this arm, InlineAssembly
  -- would fall through to the statement catch-all.
  | .InlineAssembly _ yulAnn =>
    -- A block whose Yul AST is unreadable may do anything.
    assemblyModel ctx ((yulSummary? yulAnn.val).getD (.any (assemblyAssignable ctx)))

  | .ExpressionStatement _ (.Literal _ valAnn kindAnn subAnn) =>
    -- Legacy __assembly__ marker (pre-InlineAssembly-op). Kept for backward
    -- compatibility with any Ion produced by an older solast.py. There is
    -- no Yul AST, so every Solidity variable in scope may be assigned.
    if valAnn.val == "__assembly__" && kindAnn.val == "string" then
      assemblyModel ctx (.any (assemblyAssignable ctx))
    else
      translateExpr ctx (.ExpressionStatement default (.Literal default valAnn kindAnn subAnn))

  | .ExpressionStatement _ expr => translateExpr ctx expr

  | .Return _ exprOpt =>
    match exprOpt with
    | .some_node _ expr => do
      let e ← translateExpr ctx expr
      match ctx.valuedReturnTarget with
      | some outName =>
        -- The procedure has multiple output parameters (declared return +
        -- mapping-state outputs); Laurel's EliminateValueReturns rejects a
        -- valued `return` there. Desugar: `<out> := e; return`.
        return mkStmtExprMd (.Block [
          mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier outName))] e),
          mkStmtExprMd (.Return none)] none)
      | none =>
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
    -- Labels for break/continue. Nested loops get distinct labels via the counter.
    let n := ctx.loopLabelCounter
    let breakLbl := s!"break_{n}"
    let contLbl := s!"continue_{n}"
    let bodyCtx := { ctx with currentLoopLabels := some (breakLbl, contLbl),
                              loopLabelCounter := n + 1 }
    let (invariants, bodyStmt) ← extractAndTranslateLoopInvariants bodyCtx body
    let (loopCond, guard) := loopHead condExpr breakLbl
    -- body wrapped in continue-labelled block; loop wrapped in break-labelled block
    let contBlock := mkStmtExprMd (.Block [bodyStmt] (some contLbl))
    let loopBody := if guard.isEmpty then contBlock else mkStmtExprMd (.Block (guard ++ [contBlock]) none)
    let whileStmt := mkStmtExprMd (.While loopCond invariants none loopBody false)
    return mkStmtExprMd (.Block [whileStmt] (some breakLbl))

  | .DoWhileStatement _ cond body => do
    -- Desugar: do { body } while (cond)  →  { body; while (cond) { body } }
    -- The leading body executes once unconditionally; the while replays it.
    --
    -- Label placement: BOTH the first iteration and the while replay live
    -- inside the break-labelled block, and the first iteration gets its own
    -- continue-labelled block. This makes `break`/`continue` in the FIRST
    -- iteration behave correctly:
    --   break    → Exit break_n    → exits past the while (loop over)
    --   continue → Exit continue_n → exits firstBody's block, landing at the
    --              while (i.e. the condition check — do-while continue
    --              semantics). Labels are lexically scoped in
    --              StructuredToUnstructured, so the sibling contLbl block
    --              inside the while does not clash.
    -- (Previously firstBody sat OUTSIDE the labelled blocks; its Exit was
    -- uncaught, fell through into the while, and re-ran the loop.)
    let condExpr ← translateExpr ctx cond
    let n := ctx.loopLabelCounter
    let breakLbl := s!"break_{n}"
    let contLbl := s!"continue_{n}"
    let bodyCtx := { ctx with currentLoopLabels := some (breakLbl, contLbl),
                              loopLabelCounter := n + 1 }
    let (invariants, bodyStmt) ← extractAndTranslateLoopInvariants bodyCtx body
    let firstBody ← translateStmt bodyCtx body
    let firstBlock := mkStmtExprMd (.Block [firstBody] (some contLbl))
    let (loopCond, guard) := loopHead condExpr breakLbl
    let contBlock := mkStmtExprMd (.Block [bodyStmt] (some contLbl))
    let loopBody := if guard.isEmpty then contBlock else mkStmtExprMd (.Block (guard ++ [contBlock]) none)
    let whileStmt := mkStmtExprMd (.While loopCond invariants none loopBody false)
    return mkStmtExprMd (.Block [firstBlock, whileStmt] (some breakLbl))

  | .BreakStatement _ =>
    match ctx.currentLoopLabels with
    | some (breakLbl, _) => return mkStmtExprMd (.Exit breakLbl)
    | none => throw (.unsupported "break outside of a loop")

  | .ContinueStatement _ =>
    match ctx.currentLoopLabels with
    | some (_, contLbl) => return mkStmtExprMd (.Exit contLbl)
    | none => throw (.unsupported "continue outside of a loop")

  | .TryStatement _ externalCall clausesSeq => do
    -- Model try/catch as a nondeterministic choice between the success path
    -- (clause 0, the call's `returns` body) and the catch path(s). The
    -- external call result and any revert reason are unknown, so each clause's
    -- parameters are introduced as havoc'd locals and both branches explored.
    -- Sound over-approximation: any state either branch reaches is reachable.
    let _ ← translateExpr ctx externalCall
    let clauses := clausesSeq.val.toList
    let mut branches : List StmtExprMd := []
    for clause in clauses do
      match clause with
      | .TryCatchClause _ _ paramsOpt block => do
        -- Introduce clause parameters (e.g. `returns (uint256 val)` or
        -- `catch Error(string memory reason)`) as havoc'd local declarations.
        let mut prelude : List StmtExprMd := []
        match paramsOpt with
        | .some_node _ (.ParameterList _ paramSeq) =>
          for p in paramSeq.val.toList do
            match p with
            | .VariableDeclaration _ pName pTypeOpt _ _ _ _ _ _ _ _ =>
              let solTy := match pTypeOpt with
                | .some_type_name _ tn => translateTypeNode ctx tn
                | .missing_type_name _ => { highType := mkHighTypeMd .TInt, solName := "uint256" }
              prelude := prelude ++ [mkStmtExprMd (mkLocalVar pName.val solTy.highType (some (mkStmtExprMd .Hole)))]
              -- The returned value is a value of its Solidity type.
              if let some c := mkRangeCond solTy.solName (mkStmtExprMd (mkIdentifier pName.val)) then
                prelude := prelude ++ [mkStmtExprMd (mkAssume c)]
            | _ => pure ()
        | _ => pure ()
        let b ← translateStmt ctx block
        branches := branches ++ [mkStmtExprMd (.Block (prelude ++ [b]) none)]
      | _ => pure ()
    -- Nondeterministic selection: nest each branch under an `if *` (Hole cond).
    let nondet := branches.foldr (fun br acc =>
      mkStmtExprMd (.IfThenElse (mkStmtExprMd .Hole) br (some acc)))
      (mkStmtExprMd (.Block [] none))
    return nondet

  | .ForStatement _ initOpt condOpt loopOpt body => do
    -- Desugar: for (init; cond; loop) body → { init; while (cond) { body; loop } }
    let mut stmts : List StmtExprMd := []
    -- Init. A variable it declares is a local for the condition, the body
    -- and the increment (it shadows a state variable of the same name).
    let mut ctx := ctx
    match initOpt with
    | .some_node _ initNode => do
      let s ← translateStmt ctx initNode
      stmts := [s]
      match initNode with
      | .VariableDeclarationStatement _ declsSeq _ =>
        for d in declsSeq.val.toList do
          if let .some_node _ (.VariableDeclaration _ nameAnn ..) := d then
            ctx := { ctx with localNames := ctx.localNames ++ [nameAnn.val] }
      | _ => pure ()
    | .missing_node _ => pure ()
    -- Condition (default to true if missing)
    let condExpr ← match condOpt with
      | .some_node _ condNode => translateExpr ctx condNode
      | .missing_node _ => pure (mkStmtExprMd (.LiteralBool true))
    -- Labels for break/continue.
    let n := ctx.loopLabelCounter
    let breakLbl := s!"break_{n}"
    let contLbl := s!"continue_{n}"
    let bodyCtx := { ctx with currentLoopLabels := some (breakLbl, contLbl),
                              loopLabelCounter := n + 1 }
    -- Get loop invariants from NatSpec and translate loop body
    let (invariants, bodyStmt) ← extractAndTranslateLoopInvariants bodyCtx body
    -- `continue` exits the body block but the increment still runs afterward.
    let contBlock := mkStmtExprMd (.Block [bodyStmt] (some contLbl))
    -- Loop body + increment
    let (loopCond, guard) := loopHead condExpr breakLbl
    let loopBody ← match loopOpt with
      | .some_node _ loopNode => do
        let loopStmt ← translateStmt bodyCtx loopNode
        pure (mkStmtExprMd (.Block (guard ++ [contBlock, loopStmt]) none))
      | .missing_node _ =>
        pure (if guard.isEmpty then contBlock else mkStmtExprMd (.Block (guard ++ [contBlock]) none))
    let whileStmt := mkStmtExprMd (.While loopCond invariants none loopBody false)
    stmts := stmts ++ [mkStmtExprMd (.Block [whileStmt] (some breakLbl))]
    return mkStmtExprMd (.Block stmts none)

  | .VariableDeclarationStatement _ declsSeq initOpt => do
    -- Extract variable declarations
    let decls := declsSeq.val.toList
    match decls with
    | [] => throw (.internalError "Empty VariableDeclarationStatement")
    | [declOpt] =>
      match declOpt with
      | .some_node _ (.VariableDeclaration _ nameAnn typeNameOpt _stateVar _const _ _ _ storageLocAnn _ _) =>
        let solTy := match typeNameOpt with
          | .some_type_name _ tn => translateTypeNode ctx tn
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
          return mkStmtExprMd (mkLocalVar nameAnn.val solTy.highType initVal)
      | .some_node _ _ =>
        throw (.unsupported "Non-VariableDeclaration in VariableDeclarationStatement")
      | .missing_node _ =>
        throw (.unsupported "Missing declaration in VariableDeclarationStatement")
    | _ =>
      -- Tuple/multi-variable declarations `(a, b) = f()`: declare each
      -- variable with a havoc'd (nondeterministic) initial value. This is
      -- the sound over-approximation — the values are unknown but the
      -- names are in scope for subsequent statements.
      -- (Previously this emitted assume(false), which silently made every
      -- POST-declaration obligation vacuous — the #26 anti-pattern — and
      -- left the names undeclared, causing resolution failures.)
      let mut declStmts : List StmtExprMd := []
      for declOpt in decls do
        match declOpt with
        | .some_node _ (.VariableDeclaration _ nameAnn typeNameOpt _ _ _ _ _ _ _ _) =>
          let solTy := match typeNameOpt with
            | .some_type_name _ tn => translateTypeNode ctx tn
            | .missing_type_name _ => { highType := mkHighTypeMd .TInt, solName := "uint256" }
          declStmts := declStmts ++
            [mkStmtExprMd (mkLocalVar nameAnn.val solTy.highType (some (mkStmtExprMd .Hole)))]
        | _ => pure ()  -- skipped tuple slot `(, b) = ...`
      return mkStmtExprMd (.Block declStmts none)

  | .Assignment _ _ _ _ => translateExpr ctx n

  -- Events: emit is a no-op for verification (no state change).
  | .EmitStatement _ _ => return mkStmtExprMd (.Block [] none)

  -- Revert: unconditional abort — assume(false) makes the path unreachable,
  -- which is sound (postconditions assume non-reverting execution).
  | .RevertStatement _ _ => return mkStmtExprMd (mkAssume (mkStmtExprMd (.LiteralBool false)))

  -- Expression nodes that appear as statements (e.g., function calls, postfix ops).
  -- A statement that cannot be translated is an error: treating it as an
  -- unconditional abort (`assume false`) would silently make every later
  -- obligation on the path hold.
  | _ => translateExpr ctx n

end

end Strata.Solidity
