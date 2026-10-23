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

/-- The storage reference (`Info storage d = data;`) that an assignment
    target such as `d.value` or `d.items[i]` writes through, if any. Writes
    through a storage reference are not modelled: its fields are read into
    locals, and writing those does not write the storage. -/
def storageRefTarget? (ctx : TransCtx) : Solidity.node SourceRange → Option String
  | .Identifier _ a => if ctx.storageAliases.any (·.1 == a.val) then some a.val else none
  | .MemberAccess _ e _ => storageRefTarget? ctx e
  | .IndexAccess _ e _ => storageRefTarget? ctx e
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
    value: anything but literals, variables, conditionals, map reads,
    transaction constants (`block.timestamp`, `this`) and operators without
    a precondition (so `k++`, an assignment, a call, a division). Laurel
    lifts such parts out of the expression, evaluating them before it. -/
def hasEffects (e : StmtExprMd) : Bool :=
  anyStmtExpr (fun e => match e.val with
    | .LiteralInt _ | .LiteralBool _ | .LiteralString _ | .Var (.Local _) | .Var (.Field ..)
    | .IfThenElse .. => false
    | .StaticCall callee args _ =>
      match asPrimOp? e.val with
      | some (op, _) => (op matches .Div | .Mod | .DivT | .ModT)
      | none => !["select", "mapConst"].contains callee.text &&
          !(args.isEmpty && envConstants.any (·.1 == callee.text))
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

/-- The variables a translated expression may write (`x` for a local or
    mapping, `#f` for the field `f` of the contract, `#*` for any field: a
    call of a mutating internal function, which takes `self`), and those it
    reads. Translator temporaries (`__…`) are not counted. -/
def writesAndReads (ctx : TransCtx) (e : StmtExprMd) : List String × List String :=
  let target : Variable → List String
    | .Local id => if id.text.startsWith "__" then [] else [id.text]
    | .Field _ f => [s!"#{f.text}"]
    | _ => []
  foldStmtExpr (fun n (w, r) => match n.val with
    | .Assign targets _ => (w ++ targets.flatMap (target ·.val), r)
    | .IncrDecr _ _ t => (w ++ target t.val, r)
    | .StaticCall callee args _ =>
      let isSelf (a : StmtExprMd) : Bool := match a.val with
        | .Var (.Local id) => id.text == "self"
        | _ => false
      let readOnly := match ctx.functionSigs.lookup ((callee.text.drop (ctx.contractName.length + 1)).toString) with
        | some sig => sig.isView || sig.isPure
        | none => false
      if args.any isSelf && !readOnly then (w ++ ["#*"], r) else (w, r)
    | .Var v => (w, r ++ target v)
    | _ => (w, r)) ([], []) e

/-- Whether one operand writes something the other may read (`f() + x`
    where `f` writes `x`, `++a + a`). -/
def operandsConflict (ctx : TransCtx) (l r : StmtExprMd) : Bool :=
  let (wl, rl) := writesAndReads ctx l
  let (wr, rr) := writesAndReads ctx r
  let hits (ws rs : List String) := ws.any fun w =>
    rs.contains w || (w == "#*" && rs.any (·.startsWith "#")) || (w.startsWith "#" && rs.contains "#*")
  hits wl rr || hits wr rl

/-- Where an operation is not modelled (an event, an Ether transfer, a
    low-level call), its arguments still run: those with effects (`x++`, an
    internal call), each bound to a local `<pre>_<i>`, in order, before
    `value` (the operation's result, if any). -/
def withArgumentEffects (pre : String) (args : List StmtExprMd) (value : Option StmtExprMd)
    : StmtExprMd :=
  let effects := args.zipIdx.filterMap fun (e, i) =>
    if hasEffects e then some (declareLocal s!"{pre}_{i}" e) else none
  match effects, value with
  | [], some v => v
  | _, _ => mkStmtExprMd (.Block (effects ++ value.toList) none)

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
    (dests : Option (List (AstNode Variable)) := none)
    : Except TranslationError StmtExprMd := do
  let ident (n : String) := mkStmtExprMd (mkIdentifier n)
  -- The order in which solc evaluates arguments is unspecified too.
  for (a, i) in args.zipIdx do
    if (args.drop (i + 1)).any (operandsConflict ctx a ·) then
      throw (.unsupported s!"the arguments of `{callee}`: one changes a variable another reads, and solc's evaluation order of arguments is unspecified")
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
  -- A memory array of the caller is passed by reference: the callee may
  -- write its elements, which are unknown afterwards.
  let memArgs := argNodes.zipIdx.filterMap fun (node, i) =>
    if !sig.memArrayParams.getD i false then none else match node with
      | .Identifier _ a => if ctx.memoryArrayParams.contains a.val then some a.val else none
      | _ => none
  let havocs := memArgs.map fun a => mkStmtExprMd (.Assign [toAssignTarget (ident a)]
    (mkStmtExprMd (.Hole (deterministic := false))))
  -- The call's statements, then the havocs, then its value (if any).
  let finish (stmts : List StmtExprMd) (value : Option StmtExprMd) : StmtExprMd :=
    match stmts, havocs, value with
    | [], [], some v => v
    | [s], [], none => s
    | _, _, _ => mkStmtExprMd (.Block (stmts ++ havocs ++ value.toList) none)
  -- A call used as a value, with the havocs after it.
  let asValue (call : StmtExprMd) : StmtExprMd :=
    if havocs.isEmpty then call
    else if sig.returnTypes.isEmpty then finish [call] none
    else
      let tmp := s!"__ret{sr.start.byteIdx}_0"
      finish [declareLocal tmp call] (some (ident tmp))
  -- `(a, b) = f(…)`: the declared return values go to `dests`, and a
  -- mutating callee's state outputs to the caller's state variables.
  let assignTo (ds : List (AstNode Variable)) (call : StmtExprMd) (stateVars : List String) :
      Except TranslationError StmtExprMd := do
    if ds.length != sig.returnTypes.length then
      throw (.typeError s!"`{callee}` returns {sig.returnTypes.length} value(s), not {ds.length}")
    let stateTargets : List (AstNode Variable) :=
      stateVars.map fun n => { val := .Local (mkIdent n), source := .unknown }
    return finish [withSourceRange ctx sr (mkStmtExprMd (.Assign (ds ++ stateTargets) call))] none
  if sig.isPure then
    let call := withSourceRange ctx sr (mkStmtExprMd (mkCall callee userArgs))
    match dests with
    | some ds => return ← assignTo ds call []
    | none => return asValue call
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
  if let some ds := dests then
    return ← assignTo ds call (if sig.isView then [] else stateVars)
  if sig.isView || stateVars.isEmpty then return asValue call
  -- Mutating callee: bind the declared returns to fresh locals and the
  -- state outputs to the caller's state variables.
  let temps := sig.returnTypes.zipIdx.map fun (ty, i) => (s!"__ret{sr.start.byteIdx}_{i}", ty)
  let targets : List (AstNode Variable) :=
    temps.map (fun (n, ty) => { val := .Declare { name := n, type := some ty }, source := .unknown }) ++
    stateVars.map fun n => { val := .Local (mkIdent n), source := .unknown }
  let assign := withSourceRange ctx sr (mkStmtExprMd (.Assign targets call))
  match temps with
  | [(n, _)] => return finish [assign] (some (ident n))
  | _ => return finish [assign] none

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

/-- Statements giving the contract's state unknown values of their
    Solidity types: every state variable but the immutables (a scalar is a
    field of `self`, except in constructors, where it is an output variable
    like mapping state), the length of each dynamic array, and the locals
    holding the fields of storage references (`d__value`), which read that
    state. -/
def stateHavoc (ctx : TransCtx) : List StmtExprMd :=
  let fresh := mkStmtExprMd (.Hole (deterministic := false))
  let assign (target : StmtExprMd) := mkStmtExprMd (.Assign [toAssignTarget target] fresh)
  let ident (n : String) := mkStmtExprMd (mkIdentifier n)
  let assume (c : StmtExprMd) := mkStmtExprMd (mkAssume c)
  let vars := ctx.stateVarNames.filter (!ctx.immutableNames.contains ·)
  let state := vars.flatMap fun n =>
    let v := if ctx.hasSelfParam && !ctx.mappingStateVars.contains n
      then mkStmtExprMd (mkFieldSelect (ident "self") n) else ident n
    let len := ident s!"{n}_length"
    assign v :: (((ctx.fieldSolTypes.lookup n).bind (mkRangeCond · v)).toList.map assume) ++
    if ctx.arrayStateVars.contains n && (ctx.fixedArrayLengths.lookup n).isNone then
      [assign len, assume (mkStmtExprMd (mkPrimOp .Geq [len, mkStmtExprMd (.LiteralInt 0)]))]
    else []
  state ++ ctx.storageAliases.flatMap fun (a, info) =>
    info.fields.map fun (f, _) => assign (ident s!"{a}__{f}")

/-- The model of an inline-assembly block with summary `s`. Yul is not
    interpreted: whatever the block may write is unknown afterwards, and
    it may end the function there.
    - The Solidity variables it assigns get fresh values, a memory array
      with its length; so does every variable in memory if it writes memory.
    - If it may write storage, so does all of the contract's state
      (`stateHavoc`), where solc lets assembly write it (not in `view` and
      `pure` functions).
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
  let state := if s.writesStorage && ctx.mayWriteState then stateHavoc ctx else []
  let havocs := vars.eraseDups.map (assign ∘ ident) ++ state
  let exit := if !s.exits then [] else
    [mkStmtExprMd (.IfThenElse fresh
      (mkStmtExprMd (.Block (ctx.returnNames.map (assign ∘ ident) ++ [mkStmtExprMd (.Return none)]) none))
      none)]
  return mkStmtExprMd (.Block (havocs ++ exit) none)

/-- How a call of code outside the contract may change the contract. -/
inductive ExternalCallKind where
  /-- `staticcall`, or a `view` or `pure` external function: it cannot
      change any state. -/
  | static
  /-- A mutating external function, `call`, or the creation of a contract:
      the code it runs may call back into the contract (re-enter it) and
      change its state through its external functions. -/
  | call
  /-- `delegatecall`: the code it runs works on the contract's storage,
      which it may change arbitrarily. -/
  | delegate
  deriving BEq

/-- The attributes of a function type as solc writes it, the words between
    its parameter list and `returns`: `[view, external]` for
    `function (address) view external returns (uint256)`. -/
def functionTypeAttributes (ts : String) : List String :=
  if !ts.startsWith "function " then [] else
    let rest := String.ofList (afterParams (ts.drop 9).toString.toList 0)
    ((rest.splitOn " returns ").headD "").splitOn " " |>.filter (!·.isEmpty)
where
  /-- What follows the parenthesized list the characters start with. -/
  afterParams : List Char → Nat → List Char
    | [], _ => []
    | '(' :: cs, d => afterParams cs (d + 1)
    | ')' :: cs, 1 => cs
    | ')' :: cs, d => afterParams cs (d - 1)
    | _ :: cs, d => afterParams cs d

/-- The kind of a call of a function of solc type `fnType?` (`member?`: the
    member called, in `a.f(…)`) if it runs code outside the contract: a
    call of an external function (another contract's, `this.f()`, through
    an external function pointer), or an address's low-level `call`,
    `delegatecall` or `staticcall`. Calls of internal and library
    functions, and `send`/`transfer`, whose callee gets too little gas to
    change any state, are not. -/
def externalCallKind? (fnType? : Option String) (member? : Option String) : Option ExternalCallKind :=
  let attrs := (fnType?.map functionTypeAttributes).getD []
  if attrs.contains "external" then
    some (if attrs.contains "view" || attrs.contains "pure" then .static else .call)
  else match member? with
    | some "call" => some .call
    | some "delegatecall" => some .delegate
    | some "staticcall" => some .static
    | _ => none

/-- The model of running code outside the contract by a call of kind
    `kind` at `sr`, after its target and arguments are evaluated:
    - `static`: no state changes;
    - `call`: the code may call back into the contract (re-enter it), so
      the contract's state is unknown afterwards (`stateHavoc`). The
      contract's external functions keep its invariants: at an entry point
      (which assumes them), the invariants are checked before the call and
      assumed after it. Nothing changes in a constructor (nothing can call
      a contract that has no code yet), nor under `--assume-no-reentrancy`;
    - `delegate`: the code works on the contract's storage, which is
      unknown afterwards, invariants included.
    State changes only where solc lets the function change it (not in
    `view` and `pure` functions). -/
def externalCallModel (ctx : TransCtx) (sr : SourceRange) (kind : ExternalCallKind)
    : List StmtExprMd :=
  let changesState := ctx.mayWriteState && match kind with
    | .static => false
    | .call => !ctx.isConstructor && !ctx.assumeNoReentrancy
    | .delegate => true
  if !changesState then []
  else if kind == .delegate then stateHavoc ctx
  else
    let invs := ctx.reentryInvariants.map fun (inv, text) => (withSourceRangeDeep ctx sr inv, text)
    invs.map (fun (inv, text) => mkStmtExprMdAnn ctx sr
        (mkAssert inv (some s!"invariant {text} holds before the external call"))) ++
      stateHavoc ctx ++ invs.map (fun (inv, _) => mkStmtExprMd (mkAssume inv))

/-- The value returned by the external call at `sr`, by solc's type of the
    call: a value of the returned elementary type, held in a fresh local
    `__ret<offset>_0` (the statements declaring it, and the value), an
    unknown value for another type or several values (which only a tuple
    declaration takes, see `translateTupleDecl`), and none for no value. -/
def externalResult (ctx : TransCtx) (sr : SourceRange) : List StmtExprMd × Option StmtExprMd :=
  let fresh := mkStmtExprMd (.Hole (deterministic := false))
  match ctx.typeAt? sr "FunctionCall" with
  | some "tuple()" => ([], none)
  | some ts =>
    let solName := if ts.startsWith "contract " then "address" else (ts.splitOn " ").headD ""
    if solName == "bool" || (solTypeRange? solName).isSome then
      let x := s!"__ret{sr.start.byteIdx}_0"
      let v := mkStmtExprMd (mkIdentifier x)
      (mkStmtExprMd (mkLocalVar x (translateTypeName solName).highType (some fresh)) ::
        (mkRangeCond solName v).toList.map (mkStmtExprMd ∘ mkAssume), some v)
    else ([], some fresh)
  | none => ([], some fresh)

/-- A call that runs code outside the contract, in parts (a `try` runs them
    on different paths). -/
structure ExternalCall where
  /-- The evaluation of its target, call options and arguments. -/
  effects : List StmtExprMd
  /-- The call itself (see `externalCallModel`). -/
  call : List StmtExprMd
  /-- The statements declaring its value, and the value, if any. -/
  result : List StmtExprMd × Option StmtExprMd

/-- The call as an expression. -/
def ExternalCall.toExpr (c : ExternalCall) : StmtExprMd :=
  match c.effects ++ c.call ++ c.result.1, c.result.2 with
  | [], some v => v
  | stmts, v => mkStmtExprMd (.Block (stmts ++ v.toList) none)

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

/-- An integer type of solc: `uintN`, `intN`, `address` (as `uint160`). -/
structure IntType where
  signed : Bool
  bits : Nat
  deriving BEq

/-- The integer type a solc type string names (`uint8`, `int256`,
    `address payable`), if any: not a literal's `int_const`, `bytesN`, an
    enum. -/
def IntType.ofString? (ts : String) : Option IntType :=
  let base := (ts.splitOn " ").headD ""
  let bits (rest : String) : Option Nat := if rest.isEmpty then some 256 else rest.toNat?
  if base == "address" then some ⟨false, 160⟩
  else if base.startsWith "uint" then (bits (base.drop 4).toString).map (⟨false, ·⟩)
  else if base.startsWith "int" then (bits (base.drop 3).toString).map (⟨true, ·⟩)
  else none

/-- The value of a constant expression, from solc's type of it
    (`int_const 7`, `int_const -128`). solc evaluates constant expressions
    exactly, with rational intermediate values (`(7 / 2) * 2` is 7, not 6),
    and with every unit and exponent applied (`2.5 ether`, `1e18`). `none`
    for any other type, and for a value solc abbreviates in the type string
    (`int_const 1157...(70 digits)...9935`). -/
def intConstValue? (ts : String) : Option Int :=
  match ts.splitOn " " with
  | ["int_const", v] => v.toInt?
  | _ => none

/-- The width in bytes of a solc `bytesN` type string (not dynamic `bytes`). -/
def bytesWidth? (ts : String) : Option Nat :=
  let base := (ts.splitOn " ").headD ""
  if base.startsWith "bytes" then (base.drop 5).toString.toNat? else none

/-- `e` truncated to `t` as the EVM does (two's complement): modulo
    `2^bits`, re-centred for a signed type. `$intMod` is the prelude's
    unchecked Euclidean modulus (no divisor check for the constant). -/
def wrapTo (t : IntType) (e : StmtExprMd) : StmtExprMd :=
  let lit (n : Int) := mkStmtExprMd (.LiteralInt n)
  let mod (x : StmtExprMd) := mkStmtExprMd (mkCall "$intMod" [x, lit (2 ^ t.bits)])
  if t.signed then
    let half : Int := 2 ^ (t.bits - 1)
    mkStmtExprMd (mkPrimOp .Sub [mod (mkStmtExprMd (mkPrimOp .Add [e, lit half])), lit half])
  else mod e

/-- `e`, an integer that bitwise operations left anywhere in `[0, 2^256)`,
    reduced to a value of the result type `t?`: wrapping maps that interval
    onto every value of `t`, so a signed result can be negative and a narrow
    one stays narrow. (An unsigned 256-bit result needs nothing.) -/
def bitsInType (t? : Option IntType) (e : StmtExprMd) : StmtExprMd :=
  match t? with
  | some t => if t.signed || t.bits < 256 then wrapTo t e else e
  | none => e

/-- The value `e`, of solc type `src?`, converted to the solc type `dst?`
    as an explicit conversion does. Integers: a conversion that cannot lose
    a value (to a type of the same signedness and at least the width, or
    from unsigned to a wider signed type) is the identity, any other one
    truncates (`uint8(300) == 44`, `int8(uint8(200)) == -56`); with an
    unknown source, truncating is right for any integer. `bytesN` keeps its
    high-order bytes: shortening divides, lengthening multiplies. Other
    conversions (to or from a contract, `bytesN` to `uintN`, address to
    `uint160`, …) keep the value. -/
def convertValue (src? dst? : Option String) (e : StmtExprMd) : StmtExprMd :=
  let lit (n : Int) := mkStmtExprMd (.LiteralInt n)
  match dst? with
  | none => e
  | some dst =>
    match IntType.ofString? dst, src? with
    | some t, some src =>
      match IntType.ofString? src with
      | some s =>
        let lossless := s.bits ≤ t.bits && (s.signed == t.signed || (!s.signed && s.bits < t.bits))
        if lossless then e else wrapTo t e
      | none => e
    | some t, none => wrapTo t e
    | none, _ =>
      match bytesWidth? dst, src?.bind bytesWidth? with
      | some n, some m =>
        if n == m then e
        else if n < m then mkStmtExprMd (mkCall "$intDiv" [e, lit (2 ^ (8 * (m - n)))])
        else mkStmtExprMd (mkPrimOp .Mul [e, lit (2 ^ (8 * (n - m)))])
      | _, _ => e

/-- The kind (solc `nodeType`) of an expression node, as in `ExprTypes`. -/
def exprKind : Solidity.node SourceRange → String
  | .BinaryOperation .. => "BinaryOperation" | .UnaryOperation .. => "UnaryOperation"
  | .FunctionCall .. => "FunctionCall" | .IndexAccess .. => "IndexAccess"
  | .MemberAccess .. => "MemberAccess" | .Conditional .. => "Conditional"
  | .Assignment .. => "Assignment" | .TupleExpression .. => "TupleExpression"
  | .FunctionCallOptions .. => "FunctionCallOptions" | .Identifier .. => "Identifier"
  | .Literal .. => "Literal" | _ => ""

/-- Source range of an expression node (`none` for other node kinds). -/
def exprRange : Solidity.node SourceRange → SourceRange
  | .BinaryOperation sr .. | .UnaryOperation sr .. | .FunctionCall sr .. | .IndexAccess sr ..
  | .MemberAccess sr .. | .Conditional sr .. | .Assignment sr .. | .TupleExpression sr ..
  | .FunctionCallOptions sr .. | .Identifier sr .. | .Literal sr .. => sr
  | _ => .none

/-- The conversion of `arg` (translated: `e`) by the conversion call at
    `sr`, with solc's types (see `convertValue`). A conversion to an enum
    reverts when the value is out of its range: the value is assumed in
    range. -/
def translateConversion (ctx : TransCtx) (sr : SourceRange) (arg : Solidity.node SourceRange)
    (e : StmtExprMd) : StmtExprMd :=
  let dst := ctx.typeAt? sr "FunctionCall"
  let v := convertValue (ctx.typeAt? (exprRange arg) (exprKind arg)) dst e
  let enumName := dst.bind fun d =>
    if d.startsWith "enum " then ((d.drop 5).toString.splitOn ".").getLast? else none
  match enumName.bind (fun n => ctx.enumDefs.lookup n) with
  | some members =>
    let tmp := s!"__enum{sr.start.byteIdx}"
    let t := mkStmtExprMd (mkIdentifier tmp)
    let inRange := mkStmtExprMd (mkPrimOp .And [
      mkStmtExprMd (mkPrimOp .Leq [mkStmtExprMd (.LiteralInt 0), t]),
      mkStmtExprMd (mkPrimOp .Lt [t, mkStmtExprMd (.LiteralInt members.length)])])
    mkStmtExprMd (.Block [declareLocal tmp v, mkStmtExprMd (mkAssume inRange), t] none)
  | none => v

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
    else if nameAnn.val == "this" then
      -- The contract's address: a constant of the transaction
      return mkStmtExprMd (mkCall "this_address" [])
    else
      return mkStmtExprMd (mkIdentifier nameAnn.val)

  | .Literal lsr valueAnn kindAnn subAnn =>
    -- A number has the value solc computed (see `intConstValue?`): it
    -- applies units and exponents exactly (`2.5 ether`, `1e18`).
    if kindAnn.val == "number" then
      if let some v := (ctx.typeAt? lsr "Literal").bind intConstValue? then
        return mkStmtExprMd (.LiteralInt v)
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

  | .BinaryOperation sr left right opAnn => do
    -- A constant expression has the exact value solc computed (see
    -- `intConstValue?`): `(7 / 2) * 2` is 7, where dividing step by step
    -- in integers would give 6.
    if let some v := (ctx.typeAt? sr "BinaryOperation").bind intConstValue? then
      return mkStmtExprMd (.LiteralInt v)
    let l ← translateExpr ctx left
    let r ← translateExpr ctx right
    -- The operands' type (solc's `commonType`), when it is an integer type.
    let common := (ctx.typeAt? sr "BinaryOperation.common").bind IntType.ofString?
    -- The result's type, when it is an integer type.
    let resultType := (ctx.typeAt? sr "BinaryOperation").bind IntType.ofString?
    -- solc's code generators evaluate the operands of a binary operator in
    -- different orders, so when one writes what the other reads the result
    -- depends on the compiler: rejected. (`&&` and `||` are ordered.)
    if opAnn.val != "&&" && opAnn.val != "||" && operandsConflict ctx l r then
      throw (.unsupported s!"the operands of `{opAnn.val}`: one changes a variable the other reads, and solc's evaluation order of operands differs between its code generators")
    let op ← match opAnn.val with
      | "+" => .ok Operation.Add
      | "-" => .ok Operation.Sub
      | "*" => .ok Operation.Mul
      -- Solidity rounds a signed division toward zero (`-7 / 2 == -3`)
      -- and gives `%` the sign of the dividend (`-7 % 2 == -1`): the
      -- truncating operations. For unsigned operands they agree with the
      -- Euclidean ones.
      | "/" => .ok (if common.any (·.signed) then Operation.DivT else Operation.Div)
      | "%" => .ok (if common.any (·.signed) then Operation.ModT else Operation.Mod)
      | "**" =>
        -- A constant power (`2 ** 64`) is folded; any other is not modelled.
        match l.val, r.val with
        | .LiteralInt b, .LiteralInt n =>
          if n ≥ 0 && n * (b.natAbs.log2 + 1) ≤ 4096 then
            return mkStmtExprMd (.LiteralInt (b ^ n.toNat))
          else throw (.unsupported "a constant power this large")
        | _, _ => throw (.unsupported "`**` with an operand that is not a constant")
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
      -- Bitwise operations are uninterpreted functions, except a few with
      -- a constant operand: a shift by a constant (`x >> k` divides by
      -- `2^k`, rounding down as the EVM's shifts do also for a signed `x`;
      -- `x << k` multiplies and, checked or not, wraps within `x`'s type),
      -- and an unsigned `x & (2^n - 1)` (the low `n` bits). An
      -- uninterpreted result is reduced to the result's type (see
      -- `bitsInType`): `int8(-1) & int8(-1)` is -1, which a result left in
      -- `[0, 2^256)` could never be.
      | "&" =>
        let lowBits (m : Int) : Option Nat :=
          let n := (m + 1).natAbs.log2
          if m > 0 && 2 ^ n == m + 1 then some n else none
        match common, r.val, l.val with
        | some t, .LiteralInt m, _ | some t, _, .LiteralInt m =>
          match lowBits m, t.signed with
          | some n, false =>
            let x := if r.val matches .LiteralInt _ then l else r
            return mkStmtExprMd (mkCall "$intMod" [x, mkStmtExprMd (.LiteralInt (2 ^ n))])
          | _, _ => return bitsInType resultType (mkStmtExprMd (mkCall "bit_and" [l, r]))
        | _, _, _ => return bitsInType resultType (mkStmtExprMd (mkCall "bit_and" [l, r]))
      | "|" => return bitsInType resultType (mkStmtExprMd (mkCall "bit_or" [l, r]))
      | "^" => return bitsInType resultType (mkStmtExprMd (mkCall "bit_xor" [l, r]))
      | "<<" =>
        match resultType, r.val with
        | some t, .LiteralInt k =>
          if k ≥ 0 && k < 4096 then
            return wrapTo t (mkStmtExprMd (mkPrimOp .Mul [l, mkStmtExprMd (.LiteralInt (2 ^ k.toNat))]))
          else return bitsInType resultType (mkStmtExprMd (mkCall "bit_shl" [l, r]))
        | _, _ => return bitsInType resultType (mkStmtExprMd (mkCall "bit_shl" [l, r]))
      | ">>" =>
        match resultType, r.val with
        | some _, .LiteralInt k =>
          if k ≥ 0 && k < 4096 then
            return mkStmtExprMd (mkCall "$intDiv" [l, mkStmtExprMd (.LiteralInt (2 ^ k.toNat))])
          else return bitsInType resultType (mkStmtExprMd (mkCall "bit_shr" [l, r]))
        | _, _ => return bitsInType resultType (mkStmtExprMd (mkCall "bit_shr" [l, r]))
      | o => throw (.unsupported s!"Binary operator: {o}")
    let result := mkStmtExprMd (mkPrimOp op [l, r])
    -- In `unchecked`, `+`, `-` and `*` wrap around instead of reverting.
    -- (Checked arithmetic stays unbounded: a result out of range reverts,
    -- and an execution that continues with it only adds behaviours.)
    match common with
    | some t =>
      if ctx.isInsideUnchecked && (op matches .Add | .Sub | .Mul) then return wrapTo t result
      else return result
    | none => return result

  | .UnaryOperation usr sub opAnn prefixAnn => do
    -- A constant expression (`-128`, `~0`) has the value solc computed.
    if let some v := (ctx.typeAt? usr "UnaryOperation").bind intConstValue? then
      return mkStmtExprMd (.LiteralInt v)
    -- In `unchecked`, `++`, `--` and `-` wrap around within the operand's
    -- type instead of reverting.
    let wrap (e : StmtExprMd) : StmtExprMd :=
      match ctx.isInsideUnchecked, (ctx.typeAt? usr "UnaryOperation").bind IntType.ofString? with
      | true, some t => wrapTo t e
      | _, _ => e
    if ["++", "--", "delete"].contains opAnn.val then
      if let some d := storageRefTarget? ctx sub then
        throw (.unsupported s!"writing through the storage reference `{d}`")
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
        let newVal := wrap (mkStmtExprMd (mkPrimOp (if opAnn.val == "++" then .Add else .Sub)
          [oldVar, mkStmtExprMd (.LiteralInt 1)]))
        let updateExpr ← buildNestedUpdate rootExpr keys newVal
        return mkStmtExprMd (.Block (binds ++ [
          declareLocal old read,
          mkStmtExprMd (.Assign [toAssignTarget rootExpr] updateExpr),
          if prefixAnn.val == "true" then newVal else oldVar]) none)
    let subExpr ← translateExpr ctx sub
    -- Laurel's native `++`/`--` (on a variable or field): prefix yields the
    -- new value and postfix the old one, as in Solidity (`x = i++`). In
    -- `unchecked`, the same with the new value wrapped.
    let incrDecr (mode : IncrDecrMode) (op : IncrDecrOp) : StmtExprMd :=
      if ctx.isInsideUnchecked && ((ctx.typeAt? usr "UnaryOperation").bind IntType.ofString?).isSome then
        let old := s!"__old{usr.start.byteIdx}"
        let oldVar := mkStmtExprMd (mkIdentifier old)
        let newVal := wrap (mkStmtExprMd (mkPrimOp (if op matches .Incr then .Add else .Sub)
          [oldVar, mkStmtExprMd (.LiteralInt 1)]))
        mkStmtExprMd (.Block [declareLocal old subExpr,
          mkStmtExprMd (.Assign [toAssignTarget subExpr] newVal),
          if mode matches .Pre then subExpr else oldVar] none)
      else mkStmtExprMd (.IncrDecr mode op (toAssignTarget subExpr))
    if prefixAnn.val == "true" then
      match opAnn.val with
      | "!" => return mkStmtExprMd (mkPrimOp .Not [subExpr])
      | "-" => return wrap (mkStmtExprMd (mkPrimOp .Neg [subExpr]))
      | "~" =>
        -- Exact in two's complement: `~x` is `-x - 1` for a signed `x`, and
        -- `2^N - 1 - x` for an N-bit unsigned one.
        match (ctx.typeAt? usr "UnaryOperation").bind IntType.ofString? with
        | some t =>
          let lit (n : Int) := mkStmtExprMd (.LiteralInt n)
          if t.signed then
            return mkStmtExprMd (mkPrimOp .Sub [mkStmtExprMd (mkPrimOp .Neg [subExpr]), lit 1])
          else return mkStmtExprMd (mkPrimOp .Sub [lit (2 ^ t.bits - 1), subExpr])
        | none => return mkStmtExprMd (mkCall "bit_not" [subExpr])
      | "++" => return incrDecr .Pre .Incr
      | "--" => return incrDecr .Pre .Decr
      | o => throw (.unsupported s!"Prefix unary operator: {o}")
    else
      match opAnn.val with
      | "++" => return incrDecr .Post .Incr
      | "--" => return incrDecr .Post .Decr
      | o => throw (.unsupported s!"Postfix unary operator: {o}")

  -- `new T(args)` parses as FunctionCall(NewExpression(T), args). Contract
  -- creation runs the new contract's constructor, outside this contract
  -- (see `translateExternalCall?`); a dynamic memory array
  -- (`new uint[](n)`) is a fresh unconstrained value. Must precede the
  -- general FunctionCall arm (matched top-to-bottom).
  | .FunctionCall sr (.NewExpression _ _) argsSeq _ _ => do
    if let some c ← translateExternalCall? ctx n then return c.toExpr
    let args ← argsSeq.val.toList.mapM (translateExpr ctx)
    return withArgumentEffects s!"__arg{sr.start.byteIdx}" args
      (some (mkStmtExprMd (.Hole (deterministic := false))))

  | .FunctionCall sr fnExpr argsSeq kindAnn namesSeq => do
    if let some c ← translateExternalCall? ctx n then return c.toExpr
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
      -- Type conversion: address(0), uint256(x), uint8(x), … (see
      -- `translateConversion`).
      let args ← argsSeq.val.toList.mapM (translateExpr ctx)
      match args, argsSeq.val.toList with
      | [arg], [argNode] => return translateConversion ctx sr argNode arg
      | _, _ => throw (.typeError "Type conversion expects exactly one argument")
    | _ =>
    -- Regular function call (kind = "functionCall")
    match fnExpr with
    | .Identifier _ nameAnn =>
      let args ← argsSeq.val.toList.mapM (translateExpr ctx)
      match nameAnn.val with
      | "require" =>
        -- `require(cond)`, `require(cond, "msg")`, `require(cond, E(args))`:
        -- assume `cond` (no source metadata: assumes produce no VCs).
        -- Every argument is evaluated before the check, even when `cond`
        -- holds (Solidity docs, "require arguments are evaluated
        -- unconditionally"), so the effects of a message such as `f()`, or
        -- of the arguments of a custom error `E(f())`, happen on the passing
        -- path too. The message's value is only used when reverting, so
        -- only its effects are kept; a custom error itself has none.
        match argsSeq.val.toList, args with
        | _ :: msgNodes, cond :: msgs =>
          let mut effects : List StmtExprMd := []
          for (node, msg) in msgNodes.zip msgs do
            match node with
            | .FunctionCall _ errFn errArgsSeq _ _ =>
              if (ctx.typeAt? (exprRange errFn) (exprKind errFn)).any (·.endsWith "returns (error)") then
                effects := effects ++ (← errArgsSeq.val.toList.mapM (translateExpr ctx)).filter hasEffects
              else if hasEffects msg then effects := effects ++ [msg]
            | _ => if hasEffects msg then effects := effects ++ [msg]
          -- solc's order of evaluating the arguments is not specified, so
          -- an effect that changes what another argument reads is rejected
          -- (as for any call).
          let operands := cond :: effects
          for (a, i) in operands.zipIdx do
            if (operands.drop (i + 1)).any (operandsConflict ctx a ·) then
              throw (.unsupported "the arguments of `require`: one changes a variable another reads, and solc's evaluation order of arguments is unspecified")
          if effects.isEmpty then return mkStmtExprMd (mkAssume cond)
          return mkStmtExprMd (.Block (effects ++ [mkStmtExprMd (mkAssume cond)]) none)
        | _, _ => throw (.typeError "require() needs at least one argument")
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
        -- selfdestruct(addr) ends the execution: an early return, with
        -- unknown return values (no data is returned)
        let fresh := mkStmtExprMd (.Hole (deterministic := false))
        return mkStmtExprMd (.Block (ctx.returnNames.map (fun n =>
          mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier n))] fresh)) ++
          [mkStmtExprMd (.Return none)]) none)
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
        let pre := s!"__arg{sr.start.byteIdx}"
        -- payable(addr).transfer(amount) → no-op for verification; a
        -- contract's `transfer(to, amount)` (ERC-20) → unknown result
        if args.length == 1 then return withArgumentEffects pre args none
        else return withArgumentEffects pre args (some (mkStmtExprMd (.Hole (deterministic := false))))
      else if memberAnn.val == "send" then do
        -- payable(addr).send(amount) → a fresh bool: whether it succeeded
        let args ← argsSeq.val.toList.mapM (translateExpr ctx)
        return withArgumentEffects s!"__arg{sr.start.byteIdx}" args
          (some (mkStmtExprMd (mkCall "send_result" [])))
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
      -- Type conversion: address(0), uint256(x), … (see `translateConversion`)
      let args ← argsSeq.val.toList.mapM (translateExpr ctx)
      match args, argsSeq.val.toList with
      | [arg], [argNode] => return translateConversion ctx sr argNode arg
      | _, _ => throw (.typeError s!"Type cast {typeNameAnn.val}() expects exactly one argument")
    | _ =>
      throw (.unsupported "a call of this expression")

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

  | .Assignment asr lhs rhs opAnn => do
    -- `x op= y`: `x op y`, with the target's type for the signedness of
    -- `/` and `%` and, in `unchecked`, the wrap-around of `+`, `-`, `*`;
    -- an uninterpreted bitwise result is reduced to the target's type (see
    -- `bitsInType`).
    let target := (ctx.typeAt? asr "Assignment").bind IntType.ofString?
    let signed := target.any (·.signed)
    let compound (cur rhs : StmtExprMd) : Except TranslationError StmtExprMd := do
      let arith (op : Operation) : StmtExprMd :=
        let e := mkStmtExprMd (mkPrimOp op [cur, rhs])
        match target with
        | some t => if ctx.isInsideUnchecked && (op matches .Add | .Sub | .Mul) then wrapTo t e else e
        | none => e
      let bits (f : String) : StmtExprMd := bitsInType target (mkStmtExprMd (mkCall f [cur, rhs]))
      match opAnn.val with
      | "=" => pure rhs
      | "+=" => pure (arith .Add)
      | "-=" => pure (arith .Sub)
      | "*=" => pure (arith .Mul)
      | "/=" => pure (arith (if signed then .DivT else .Div))
      | "%=" => pure (arith (if signed then .ModT else .Mod))
      | "&=" => pure (bits "bit_and")
      | "|=" => pure (bits "bit_or")
      | "^=" => pure (bits "bit_xor")
      | "<<=" => pure (bits "bit_shl")
      | ">>=" => pure (bits "bit_shr")
      | o => throw (.unsupported s!"Assignment operator: {o}")
    if let some d := storageRefTarget? ctx lhs then
      throw (.unsupported s!"writing through the storage reference `{d}`")
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
      let rhs' ← compound readExpr rhsExpr
      -- Build nested update: for m[k1][k2] = v, produce
      --   Assign [root] (update(root, k1, update(select(root, k1), k2, v)))
      let updateExpr ← buildNestedUpdate rootExpr idxExprs rhs'
      let assign := mkStmtExprMd (.Assign [toAssignTarget rootExpr] updateExpr)
      if binds.isEmpty then return assign
      return mkStmtExprMd (.Block (binds ++ [assign]) none)
    | none =>
    -- A memory array is a reference: `a = b` would make `a` and `b` the
    -- same array, which the translation (arrays as values) cannot express.
    let isMemArray (n : Solidity.node SourceRange) : Bool := match n with
      | .Identifier _ a => ctx.memoryArrayParams.contains a.val ||
          (ctx.memoryVars.lookup a.val).any (·.val matches .TMap ..)
      | _ => false
    if opAnn.val == "=" && isMemArray lhs && isMemArray rhs then
      throw (.unsupported "assigning a memory array to another (they would alias)")
    let lhsExpr ← translateExpr ctx lhs
    -- Assigning a whole array assigns its length too: the other array's, or
    -- an unknown one.
    let lengthOf (n : Solidity.node SourceRange) : Option String := match n with
      | .Identifier _ a =>
        if ctx.arrayStateVars.contains a.val || ctx.memoryArrayParams.contains a.val then
          some s!"{a.val}_length" else none
      | _ => none
    let lengthAssign : List StmtExprMd := if opAnn.val != "=" then [] else
      match lengthOf lhs with
      | some lhsLen =>
        [mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier lhsLen))]
          (match lengthOf rhs with
            | some rhsLen => mkStmtExprMd (mkIdentifier rhsLen)
            | none => mkStmtExprMd (.Hole (deterministic := false))))]
      | none => []
    -- `x op= f()`: the target is read after the right-hand side runs.
    let (binds, rhsExpr) := if opAnn.val == "=" || !hasEffects rhsExpr then ([], rhsExpr) else
      ([declareLocal rhsVar rhsExpr], mkStmtExprMd (mkIdentifier rhsVar))
    let rhs' ← compound lhsExpr rhsExpr
    let assign := mkStmtExprMd (.Assign [toAssignTarget lhsExpr] rhs')
    if binds.isEmpty && lengthAssign.isEmpty then return assign
    return mkStmtExprMd (.Block (binds ++ [assign] ++ lengthAssign) none)

  -- Call with {value:, gas:} options: the options don't affect verification
  -- semantics (ETH transfer is external/opaque). Translate the wrapped call.
  | .FunctionCallOptions _ inner _ _ => translateExpr ctx inner

  -- A bare NewExpression operand (no call args) — also opaque.
  | .NewExpression _ _ =>
    return mkStmtExprMd (.Hole (deterministic := false))

  -- Static array literal `[a, b, c]`. A faithful model requires the memory-
  -- array length-tracking representation the translator uses for other arrays;
  -- the simple fresh-map encoding conflicts with it. Until that lands, reject
  -- explicitly (sound: a clean error, never a silent vacuous pass).
  | .InlineArrayExpression _ _ =>
    throw (.unsupported "inline array literal [a, b, c] (needs memory-array length tracking)")

  -- Calldata/bytes slice `x[start:end]`. Opaque slice — fresh unconstrained
  -- value (sound over-approximation).
  | .IndexRangeAccess _ _ _ _ =>
    return mkStmtExprMd (.Hole (deterministic := false))

  | _ => throw (.unsupported s!"Expression node type")

/-- The model of `n` if it is a call that runs code outside the contract
    (see `externalCallKind?`) or creates a contract (`new C(…)`, which runs
    `C`'s constructor): its target, call options and arguments are
    evaluated in order (only their effects matter: the call's result is
    unknown), then the call runs (`externalCallModel`) and returns its
    result (`externalResult`). `none` for other calls. A `try` call
    (`isTry`) of unknown kind is taken for a mutating external call. -/
partial def translateExternalCall? (ctx : TransCtx) (n : Solidity.node SourceRange)
    (isTry : Bool := false) : Except TranslationError (Option ExternalCall) := do
  let .FunctionCall sr fnExpr argsSeq kindAnn _ := n | return none
  if kindAnn.val != "functionCall" then return none
  -- `f{value: v}(…)`: the options are evaluated with the callee.
  let (callee, options) := match fnExpr with
    | .FunctionCallOptions _ e _ opts => (e, opts.val.toList)
    | e => (e, [])
  let fnType := ctx.typeAt? (exprRange fnExpr) (exprKind fnExpr)
  let (kind?, target) := match callee with
    | .NewExpression _ (.UserDefinedTypeName ..) => (some ExternalCallKind.call, [])
    | .NewExpression .. => (none, [])
    | .MemberAccess _ base m => (externalCallKind? fnType (some m.val), [base])
    | _ => (externalCallKind? fnType none, [])
  let some kind := kind? <|> (if isTry then some .call else none) | return none
  let operands ← (target ++ options ++ argsSeq.val.toList).mapM (translateExpr ctx)
  let effectful := operands.filter hasEffects
  for (a, i) in effectful.zipIdx do
    if (effectful.drop (i + 1)).any (operandsConflict ctx a ·) then
      throw (.unsupported "the operands of an external call: one changes a variable another reads, and solc's evaluation order is unspecified")
  return some {
    effects := effectful.zipIdx.map fun (e, i) => declareLocal s!"__arg{sr.start.byteIdx}_{i}" e
    call := externalCallModel ctx sr kind
    result := externalResult ctx sr }

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
      -- A tuple declaration `(uint a, uint b) = f(…);` declares its
      -- variables in this block (not a nested one), for the statements after.
      if let .VariableDeclarationStatement sr declsSeq initOpt := stmt then
        if declsSeq.val.size > 1 then
          let (stmts, names) ← translateTupleDecl ctx sr declsSeq.val.toList initOpt
          let rest' ← translateBlockStmts { ctx with localNames := ctx.localNames ++ names } rest
          return stmts ++ rest'
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

/-- A tuple declaration `(T1 a, , T3 c) = init;`: the statements that
    declare and initialize its variables, and their names. The initializer:
    - a call of an internal function binds its return values to the
      variables (a skipped slot to a temporary), and a mutating callee's
      state outputs to the caller's state, as `translateInternalCall`;
    - a tuple `(e1, e2, e3)` initializes each variable with its component,
      evaluated in order;
    - anything else (an external call, `abi.decode`) gives the variables
      unknown values; an initializer with effects there is rejected rather
      than dropped. -/
partial def translateTupleDecl (ctx : TransCtx) (sr : SourceRange)
    (decls : List (Solidity.opt_node SourceRange)) (initOpt : Solidity.opt_node SourceRange)
    : Except TranslationError (List StmtExprMd × List String) := do
  let slots : List (Option (String × HighTypeMd)) := decls.map fun
    | .some_node _ (.VariableDeclaration _ nameAnn typeNameOpt _ _ _ _ _ _ _ _) =>
      let solTy := match typeNameOpt with
        | .some_type_name _ tn => translateTypeNode ctx tn
        | .missing_type_name _ => { highType := mkHighTypeMd .TInt, solName := "uint256" }
      some (nameAnn.val, solTy.highType)
    | _ => none
  let names := slots.filterMap (·.map (·.1))
  let fresh := mkStmtExprMd (.Hole (deterministic := false))
  match initOpt with
  | .some_node _ (.FunctionCall csr (.Identifier _ fnAnn) argsSeq kindAnn namesSeq) =>
    match kindAnn.val, ctx.functionSigs.lookup fnAnn.val with
    | "functionCall", some sig =>
      let args ← argsSeq.val.toList.mapM (translateExpr ctx)
      let argNames := namesSeq.val.toList.map (·.val)
      let (argNodes, args) ← if argNames.isEmpty then pure (argsSeq.val.toList, args) else do
        let named := argNames.zip (argsSeq.val.toList.zip args)
        let ordered ← sig.paramNames.mapM fun p => match named.lookup p with
          | some a => pure a
          | none => throw (.typeError s!"call to `{fnAnn.val}` has no argument named `{p}`")
        pure (ordered.map (·.1), ordered.map (·.2))
      let dests : List (AstNode Variable) := (slots.zip sig.returnTypes).zipIdx.map fun ((slot, retTy), i) =>
        match slot with
        | some (n, ty) => { val := .Declare { name := n, type := some ty }, source := .unknown }
        | none => { val := .Declare { name := s!"__ret{csr.start.byteIdx}_{i}", type := some retTy },
                    source := .unknown }
      if slots.length != sig.returnTypes.length then
        throw (.typeError s!"`{fnAnn.val}` returns {sig.returnTypes.length} value(s), not {slots.length}")
      let assign ← translateInternalCall ctx csr s!"{ctx.contractName}_{fnAnn.val}" sig argNodes args
        (dests := some dests)
      -- Spliced, so that the declarations are in the enclosing block.
      return (match assign.val with
        | .Block stmts none => stmts
        | _ => [assign], names)
    | _, _ => unknownInit
  | .some_node _ (.TupleExpression _ compsSeq) =>
    let comps := compsSeq.val.toList
    if comps.length != slots.length then
      throw (.typeError s!"tuple of {comps.length} component(s) for {slots.length} variable(s)")
    let mut stmts : List StmtExprMd := []
    for (slot, comp, i) in (slots.zip comps).zipIdx.map (fun ((s, c), i) => (s, c, i)) do
      let e ← translateExpr ctx comp
      match slot with
      | some (n, ty) => stmts := stmts ++ [mkStmtExprMd (mkLocalVar n ty (some e))]
      | none => if hasEffects e then stmts := stmts ++ [declareLocal s!"__ret{sr.start.byteIdx}_{i}" e]
    return (stmts, names)
  | .some_node _ _ => unknownInit
  | .missing_node _ =>
    let decls := slots.filterMap (·.map fun (n, ty) =>
      mkStmtExprMd (mkLocalVar n ty (zeroValue? ty <|> some fresh)))
    return (decls, names)
where
  unknownInit : Except TranslationError (List StmtExprMd × List String) := do
    match initOpt with
    | .some_node _ init =>
      let e ← translateExpr ctx init
      -- The initializer's effects (a low-level call's arguments) run first;
      -- its value is not modelled.
      let unsupported : TranslationError :=
        .unsupported "a tuple declaration whose initializer has effects (other than an internal call)"
      let endsInHole (stmts : List StmtExprMd) : Bool :=
        match stmts.getLast? with
        | some last => (last.val matches .Hole ..)
        | none => false
      let effects ← match e.val with
        | .Hole .. => pure []
        | .Block stmts none => if endsInHole stmts then pure stmts.dropLast else throw unsupported
        | _ => if hasEffects e then throw unsupported else pure []
      let slots := decls.filterMap fun
        | .some_node _ (.VariableDeclaration _ nameAnn typeNameOpt _ _ _ _ _ _ _ _) =>
          some (nameAnn.val, match typeNameOpt with
            | .some_type_name _ tn => (translateTypeNode ctx tn).highType
            | .missing_type_name _ => mkHighTypeMd .TInt)
        | _ => none
      let decls := slots.map fun (n, ty) =>
        mkStmtExprMd (mkLocalVar n ty (some (mkStmtExprMd (.Hole (deterministic := false)))))
      return (effects ++ decls, slots.map (·.1))
    | .missing_node _ => return ([], [])

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
    -- `_` in a modifier body: the code it stands for.
    if valAnn.val == "_" then
      match ctx.placeholder with
      | some p => return p
      | none => throw (.unsupported "`_` outside a modifier")
    -- Legacy __assembly__ marker (pre-InlineAssembly-op). Kept for backward
    -- compatibility with any Ion produced by an older solast.py. There is
    -- no Yul AST, so every Solidity variable in scope may be assigned.
    else if valAnn.val == "__assembly__" && kindAnn.val == "string" then
      assemblyModel ctx (.any (assemblyAssignable ctx))
    else
      translateExpr ctx (.ExpressionStatement default (.Literal default valAnn kindAnn subAnn))

  | .ExpressionStatement _ expr => translateExpr ctx expr

  | .Return sr exprOpt =>
    -- Under modifiers (`ctx.returnLabel`), `return` ends the function body
    -- or the modifier, not the procedure: the code after `_` still runs.
    if let some lbl := ctx.returnLabel then
      let assigns ← match exprOpt with
        | .missing_node _ => pure []
        | .some_node _ (.TupleExpression _ compsSeq) =>
          if compsSeq.val.size == ctx.returnNames.length && compsSeq.val.size > 1 then
            -- `return (a, b)`: the components first, then the outputs.
            let comps ← compsSeq.val.toList.mapM (translateExpr ctx)
            let temps := comps.zipIdx.map fun (c, i) => (s!"__retv{sr.start.byteIdx}_{i}", c)
            pure (temps.map (fun (t, c) => declareLocal t c) ++
              (ctx.returnNames.zip temps).map fun (out, (t, _)) =>
                mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier out))]
                  (mkStmtExprMd (mkIdentifier t))))
          else do
            let e ← translateExpr ctx (.TupleExpression sr compsSeq)
            pure (ctx.returnNames.take 1 |>.map fun out =>
              mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier out))] e))
        | .some_node _ expr => do
          let e ← translateExpr ctx expr
          pure (ctx.returnNames.take 1 |>.map fun out =>
            mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier out))] e))
      return withSourceRange ctx sr (mkStmtExprMd (.Block (assigns ++ [mkStmtExprMd (.Exit lbl)]) none))
    match exprOpt with
    | .some_node _ expr => do
      let e ← translateExpr ctx expr
      -- Located at the statement, so that the checks Laurel lifts out of
      -- the expression (a callee's precondition, a divisor) are too.
      match ctx.valuedReturnTarget with
      | some outName =>
        -- The procedure has multiple output parameters (declared return +
        -- mapping-state outputs); Laurel's EliminateValueReturns rejects a
        -- valued `return` there. Desugar: `<out> := e; return`.
        return mkStmtExprMd (.Block [
          withSourceRange ctx sr (mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier outName))] e)),
          mkStmtExprMd (.Return none)] none)
      | none =>
        return withSourceRange ctx sr (mkStmtExprMd (.Return (some e)))
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
    -- try/catch: the call's target and arguments are evaluated, then the
    -- call either succeeds, with its effects (see `externalCallModel`),
    -- and runs clause 0 (the `returns` body), or reverts, undoing them,
    -- and runs one of the catch clauses: a nondeterministic choice. The
    -- values returned and the revert reason are unknown, so each clause's
    -- parameters are fresh locals of their type.
    let some call ← translateExternalCall? ctx externalCall (isTry := true)
      | throw (.unsupported "a `try` of something other than an external call")
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
              prelude := prelude ++ [mkStmtExprMd (mkLocalVar pName.val solTy.highType
                (some (mkStmtExprMd (.Hole (deterministic := false)))))]
              -- The returned value is a value of its Solidity type.
              if let some c := mkRangeCond solTy.solName (mkStmtExprMd (mkIdentifier pName.val)) then
                prelude := prelude ++ [mkStmtExprMd (mkAssume c)]
            | _ => pure ()
        | _ => pure ()
        let b ← translateStmt ctx block
        let onSuccess := if branches.isEmpty then call.call else []
        branches := branches ++ [mkStmtExprMd (.Block (onSuccess ++ prelude ++ [b]) none)]
      | _ => pure ()
    -- Nondeterministic selection: each branch but the last under an `if *`
    -- (a revert that no catch clause catches propagates).
    let nondet := match branches.reverse with
      | [] => mkStmtExprMd (.Block [] none)
      | last :: rest => rest.foldl (fun acc br =>
          mkStmtExprMd (.IfThenElse (mkStmtExprMd (.Hole (deterministic := false))) br (some acc))) last
    return mkStmtExprMd (.Block (call.effects ++ [nondet]) none)

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

  | .VariableDeclarationStatement declSr declsSeq initOpt => do
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
        -- A memory array is a reference: `T[] memory a = b` would make `a`
        -- and `b` the same array (see `.Assignment`).
        if storageLocAnn.val == "memory" then
          if let .some_node _ (.Identifier _ b) := initOpt then
            if ctx.memoryArrayParams.contains b.val ||
                (ctx.memoryVars.lookup b.val).any (·.val matches .TMap ..) then
              throw (.unsupported s!"declaring `{nameAnn.val}` as the memory array `{b.val}` (they would alias)")
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
          -- Without an initializer, a Solidity local starts at zero.
          let initVal := initVal <|> zeroValue? solTy.highType
          -- Located at the statement (see `.Return`).
          return withSourceRange ctx declSr (mkStmtExprMd (mkLocalVar nameAnn.val solTy.highType initVal))
      | .some_node _ _ =>
        throw (.unsupported "Non-VariableDeclaration in VariableDeclarationStatement")
      | .missing_node _ =>
        throw (.unsupported "Missing declaration in VariableDeclarationStatement")
    | _ =>
      -- A tuple declaration outside a block (translateBlockStmts splices
      -- the ones in a block, so that later statements see the variables).
      let (stmts, _) ← translateTupleDecl ctx declSr decls initOpt
      return mkStmtExprMd (.Block stmts none)

  | .Assignment _ _ _ _ => translateExpr ctx n

  -- Events: emit is a no-op for verification (no state change).
  -- Its arguments still run (`emit Bumped(nonce++)`).
  | .EmitStatement sr (.FunctionCall _ _ argsSeq _ _) => do
    let args ← argsSeq.val.toList.mapM (translateExpr ctx)
    return withArgumentEffects s!"__arg{sr.start.byteIdx}" args none
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
