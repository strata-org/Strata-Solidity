/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

import StrataLaurel.Implementation.LaurelAST
import StrataLaurel.Implementation.LaurelCompilationPipeline
import StrataLaurel.Implementation.Grammar.ConcreteToAbstractTreeTranslator
import Strata.Languages.Core.Verifier
import StrataSolidity.SolidityDialect
import StrataSolidity.ReadSolidity
import Strata.DL.Imperative.MetaData

/-!
# Solidity AST → Laurel Translation

Translates the Solidity DDM AST (produced by solc → solast.py → Ion)
into the Laurel intermediate representation.

## Scope
- Pure/view functions with value types (uint256, int256, bool, address)
- `require(cond)` → assume, `assert(cond)` → assert
- Custom errors: `error E(...)` declarations skipped; `revert E(...)` → assume(false);
  `require(cond, E(...))` → assume(cond)
- if/else, while, for loops, return, variable declarations, assignments
- Arithmetic and comparison operators
- Contracts as CompositeType with state-variable fields + static procedures
- Struct definitions as CompositeType
- Transient storage variables (`uint256 transient x`): treated identically to
  regular state variables for single-transaction verification. Transient storage
  is cleared between transactions (EIP-1153); cross-transaction reasoning would
  need to model this reset, but within a single transaction the semantics match.

## Design (Option A from design doc)
Uses `solc --ast-json` via the external Python tooling; this module
only handles the Lean-side translation from typed DDM AST to Laurel.
-/

namespace Strata.Solidity

open Laurel

/-! ## Helpers -/

/-- Convert a SourceRange and file URI to a Laurel `FileRange` (the
    AstNode source location). Returns `FileRange.unknown` if the SourceRange
    is empty. -/
def sourceRangeToFileRange (uri : Uri) (sr : SourceRange) : FileRange :=
  if sr.isNone then .unknown
  else { file := uri, range := sr }

/-- Find the index of the first element satisfying a predicate. -/
def List.findIndex? (p : α → Bool) : List α → Option Nat
  | [] => none
  | x :: xs => if p x then some 0 else (List.findIndex? p xs).map (· + 1)

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
  /-- Whether the current function has an implicit `self` parameter in scope.
      True only for non-pure, non-constructor functions that have at least one
      non-mapping state variable (see translateFunction). Used by the inline
      assembly havoc to decide whether `self.<field>` references are valid. -/
  hasSelfParam : Bool := false
  /-- Labels of the innermost enclosing loop, as (breakLabel, continueLabel).
      Set when translating a loop body so that `break`/`continue` statements
      can emit `Exit` to the correct labelled block. `none` outside any loop. -/
  currentLoopLabels : Option (String × String) := none
  /-- Monotonic counter used to generate unique loop labels. -/
  loopLabelCounter : Nat := 0
  /-- Loop invariant expressions parsed from NatSpec `@custom:strata loop-invariant`.
      Applied to loops encountered during function body translation. -/
  loopInvariantExprs : List StmtExprMd := []
  /-- Whether we are currently inside an `unchecked { }` block.
      Solidity unchecked blocks disable overflow/underflow checks for arithmetic.
      Currently arithmetic maps directly to the `$add`/`$sub`/`$mul` operators with no overflow
      checks, so this flag is a no-op. When overflow checks are added (Phase 3
      bitvector work), this flag should suppress them. -/
  isInsideUnchecked : Bool := false
  /-- Enum definitions: maps enum name to ordered list of member names.
      Used to resolve `EnumName.Member` to integer literals. -/
  enumDefs : List (String × List String) := []
  /-- Names of user-defined value types (`type Wei is uint256`). Resolved to
      their underlying value type (modeled as TInt, like enums) so local
      declarations and parameters typed as a UDVT resolve. -/
  udvtNames : List String := []
  /-- Contract-level invariant expressions parsed from NatSpec `@custom:strata invariant`.
      These are pre-parsed StmtExprMd and don't need re-translation per function. -/
  contractInvariantNatspec : List StmtExprMd := []
  /-- Modifier definitions: maps modifier name to list of raw require statement
      DDM nodes extracted from the modifier body (pre-`_;` only).
      Translated in each function's context for correct state var resolution. -/
  modifierDefs : List (String × List (Solidity.node SourceRange)) := []
  /-- Constant state variable definitions: maps constant name to its
      compile-time value expression for constant folding. -/
  constantDefs : List (String × StmtExprMd) := []
  /-- When the current function has a declared return value AND additional
      output parameters (mapping state vars are threaded as outputs), Laurel's
      EliminateValueReturns cannot handle `return e` ("Valued return is not
      supported for procedures with multiple output parameters"). In that case
      this holds the declared return's output-parameter name, and the
      translator desugars `return e` into `<name> := e; return`. -/
  valuedReturnTarget : Option String := none

def mkHighTypeMd (ty : HighType) : HighTypeMd :=
  { val := ty, source := .unknown }

def mkStmtExprMd (expr : StmtExpr) : StmtExprMd :=
  { val := expr, source := .unknown }

/-! ### AST shape adapters

The Laurel AST changed shape across multiple upstream PRs:
- `StmtExpr.Identifier name` → `StmtExpr.Var (Variable.Local id)` (#1077)
- `StmtExpr.FieldSelect t f` → `StmtExpr.Var (Variable.Field t f)` (#1077)
- `StmtExpr.Forall/.Exists` → `StmtExpr.Quantifier mode param trigger body` (#1024)
- `Identifier` gained `uniqueId` and `source` fields (#1028)
- `StmtExpr.PrimitiveOp op args` → `StmtExpr.StaticCall op.procName args`:
  operators are calls to the reserved `$add`/`$eq`/… wrapper procedures
- `AstNode.source` became a non-optional `FileRange` (`.unknown` when absent)
- `Variable.Declare` takes a `Parameter?` (optional type annotation)

These helpers preserve the old call sites so the translator code reads
naturally without churn at every construction site. -/

/-- Construct a bare-name `Identifier` (no resolution-pass uniqueId, no source). -/
def mkIdent (name : String) : Identifier := { text := name }

/-- Build the new-style identifier reference: `StmtExpr.Var (Variable.Local …)`. -/
def mkIdentifier (name : String) : StmtExpr :=
  .Var (.Local (mkIdent name))

/-- Build the new-style field access: `StmtExpr.Var (Variable.Field target field)`. -/
def mkFieldSelect (target : StmtExprMd) (fieldName : String) : StmtExpr :=
  .Var (.Field target (mkIdent fieldName))

/-- Build a universal quantifier (no trigger). -/
def mkForall (p : Parameter) (body : StmtExprMd) : StmtExpr :=
  .Quantifier .Forall p none body

/-- Build an existential quantifier (no trigger). -/
def mkExists (p : Parameter) (body : StmtExprMd) : StmtExpr :=
  .Quantifier .Exists p none body

/-- Build a local variable declaration, optionally with an initializer.

    Replaces the legacy `StmtExpr.LocalVariable name type init` constructor.
    With `init = none`, produces `Var (Declare param)`. With an initializer,
    produces `Assign [Declare param] init` (the new shape used by upstream). -/
def mkLocalVar (name : String) (type : HighTypeMd) (init : Option StmtExprMd) : StmtExpr :=
  let param : Parameter? := { name := name, type := some type }
  match init with
  | none => .Var (.Declare param)
  | some initVal =>
    let target : AstNode Variable := { val := .Declare param, source := .unknown }
    .Assign [target] initVal

/-- Convert a StmtExprMd into an AstNode Variable suitable for use as an
    `Assign` target. Only valid when the underlying StmtExpr is a `.Var`
    (a Local or Field reference), which is exactly the shape produced by
    `mkIdentifier` and `mkFieldSelect`.

    For unsupported targets (literals, calls, etc.) this falls back to an
    `__invalid_target` Local identifier so verification will obviously fail
    rather than silently accepting nonsense. The legacy translator could
    pass arbitrary expressions as `Assign` targets; the new Laurel AST
    constrains targets to variables. -/
def toAssignTarget (e : StmtExprMd) : AstNode Variable :=
  match e.val with
  | .Var v => { val := v, source := e.source }
  | _ => { val := .Local (mkIdent "__invalid_target"), source := e.source }

/-- Build an `Assert` StmtExpr from a boolean condition expression,
    with an optional human-readable summary (unset by default). -/
def mkAssert (cond : StmtExprMd) (summary? : Option String := none) : StmtExpr :=
  .Assert cond summary?

/-- Build an `Assume` StmtExpr. The `summary?` argument is accepted for API
    parity with `mkAssert` but discarded (Laurel's `Assume` has no summary). -/
def mkAssume (cond : StmtExprMd) (_summary? : Option String := none) : StmtExpr :=
  .Assume cond

/-- Build a call to a static procedure. Type arguments are left empty:
    Laurel's resolution pass infers them for generic callees. -/
def mkCall (callee : Identifier) (args : List StmtExprMd) : StmtExpr :=
  .StaticCall callee args []

/-- Build a primitive operation. Laurel represents `x + y` as a `StaticCall`
    to the built-in wrapper procedure named by `Operation.procName` (`$add`). -/
def mkPrimOp (op : Operation) (args : List StmtExprMd) : StmtExpr :=
  mkCall (mkIdent op.procName) args

/-- Recognize a primitive operation built by `mkPrimOp`. -/
def asPrimOp? : StmtExpr → Option (Operation × List StmtExprMd)
  | .StaticCall callee args _ => (Operation.ofProcName? callee.text).map (·, args)
  | _ => none

/-- Create a StmtExprMd with source location metadata. -/
def mkStmtExprMdAnn (ctx : TransCtx) (sr : SourceRange) (expr : StmtExpr) : StmtExprMd :=
  match ctx.uri with
  | some uri => { val := expr, source := sourceRangeToFileRange uri sr }
  | none => { val := expr, source := .unknown }

/-- Attach source range metadata to an existing StmtExprMd. -/
def withSourceRange (ctx : TransCtx) (sr : SourceRange) (e : StmtExprMd) : StmtExprMd :=
  if sr == default then e
  else match ctx.uri with
  | some uri => { e with source := sourceRangeToFileRange uri sr }
  | none => e

/-! ## Translation Error -/

/-- Check if a spec string contains struct-through-mapping access (e.g., `m[k].field`).
    These are unsupported and must be filtered out before reaching Core. -/
def hasStructAccess (s : String) : Bool :=
  let chars := s.toList
  chars.zip (chars.drop 1 |>.zip (chars.drop 2)) |>.any fun (c, (c1, c2)) =>
    c == ']' && c1 == '.' && c2.isAlpha

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

/-- Translate a DDM type_name node to SolType.
    Requires TransCtx to resolve enum types to TInt. -/
def translateTypeNode (ctx : TransCtx) (tn : Solidity.type_name SourceRange) : SolType :=
  match tn with
  | .ElementaryTypeName _ nameAnn _ => translateTypeName nameAnn.val
  | .UserDefinedTypeName _ nameAnn =>
    -- Enum types and user-defined value types (UDVT) are modeled as TInt.
    if ctx.enumDefs.any (·.1 == nameAnn.val) || ctx.udvtNames.contains nameAnn.val then
      { highType := mkHighTypeMd .TInt, solName := nameAnn.val }
    else
      { highType := mkHighTypeMd (.UserDefined (mkIdent nameAnn.val)), solName := nameAnn.val }
  | .MappingType _ keyTn valTn _ _ =>
    let k := (translateTypeNode ctx keyTn).highType
    let v := (translateTypeNode ctx valTn).highType
    { highType := mkHighTypeMd (.TMap k v), solName := "mapping" }
  | .ArrayTypeName _ baseTn =>
    let elem := (translateTypeNode ctx baseTn).highType
    -- NOTE: Design doc specifies `TMap Nat T` but Laurel's HighType has no TNat variant,
    -- so we use TInt as the key type. This means array indices can be negative in the SMT
    -- encoding; we compensate by asserting idx >= 0 at each IndexAccess site.
    { highType := mkHighTypeMd (.TMap (mkHighTypeMd .TInt) elem), solName := "array" }
  | .FunctionTypeName _ _ _ _ _ =>
    -- First-class function types are modeled as an opaque user-defined type.
    -- Verification doesn't reason about function-pointer values; this keeps
    -- the type well-formed without claiming any structure.
    { highType := mkHighTypeMd (.UserDefined (mkIdent "function")), solName := "function" }

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
  | .TMap _ v => mkStmtExprMd (mkCall "const" [defaultValueForType v])
  | _ => mkStmtExprMd (.LiteralInt 0)

/-- Generate a non-negative precondition: param >= 0 -/
def mkNonNegPrecond (paramName : String) : StmtExprMd :=
  let ident := mkStmtExprMd (mkIdentifier paramName)
  let zero := mkStmtExprMd (.LiteralInt 0)
  mkStmtExprMd (mkPrimOp .Geq [ident, zero])


end Strata.Solidity
