/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

import Strata.Languages.Laurel.Laurel
import Strata.Languages.Laurel.LaurelToCoreTranslator
import Strata.Languages.Laurel.Grammar.ConcreteToAbstractTreeTranslator
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

def defaultMetadata : Imperative.MetaData Core.Expression := #[]

/-- Find the index of the first element satisfying a predicate. -/
def List.findIndex? (p : α → Bool) : List α → Option Nat
  | [] => none
  | x :: xs => if p x then some 0 else (List.findIndex? p xs).map (· + 1)

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
  /-- Loop invariant expressions parsed from NatSpec `@custom:strata loop-invariant`.
      Applied to loops encountered during function body translation. -/
  loopInvariantExprs : List StmtExprMd := []
  /-- Whether we are currently inside an `unchecked { }` block.
      Solidity unchecked blocks disable overflow/underflow checks for arithmetic.
      Currently arithmetic maps directly to PrimitiveOp.Add/Sub/Mul with no overflow
      checks, so this flag is a no-op. When overflow checks are added (Phase 3
      bitvector work), this flag should suppress them. -/
  isInsideUnchecked : Bool := false
  /-- Enum definitions: maps enum name to ordered list of member names.
      Used to resolve `EnumName.Member` to integer literals. -/
  enumDefs : List (String × List String) := []
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

def mkHighTypeMd (ty : HighType) : HighTypeMd :=
  { val := ty, md := defaultMetadata }

def mkStmtExprMd (expr : StmtExpr) : StmtExprMd :=
  { val := expr, md := defaultMetadata }

/-- Create a StmtExprMd with source location metadata. -/
def mkStmtExprMdAnn (ctx : TransCtx) (sr : SourceRange) (expr : StmtExpr) : StmtExprMd :=
  match ctx.uri with
  | some uri => { val := expr, md := sourceRangeToMd uri sr }
  | none => { val := expr, md := defaultMetadata }

/-- Attach source range metadata to an existing StmtExprMd. -/
def withSourceRange (ctx : TransCtx) (sr : SourceRange) (e : StmtExprMd) : StmtExprMd :=
  if sr == default then e
  else match ctx.uri with
  | some uri => { e with md := sourceRangeToMd uri sr }
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
  | .ElementaryTypeName _ nameAnn => translateTypeName nameAnn.val
  | .UserDefinedTypeName _ nameAnn =>
    -- Enum types are modeled as TInt (uint8 in Solidity)
    if ctx.enumDefs.any (·.1 == nameAnn.val) then
      { highType := mkHighTypeMd .TInt, solName := nameAnn.val }
    else
      { highType := mkHighTypeMd (.UserDefined ⟨nameAnn.val, none⟩), solName := nameAnn.val }
  | .MappingType _ keyTn valTn =>
    let k := (translateTypeNode ctx keyTn).highType
    let v := (translateTypeNode ctx valTn).highType
    { highType := mkHighTypeMd (.TMap k v), solName := "mapping" }
  | .ArrayTypeName _ baseTn =>
    let elem := (translateTypeNode ctx baseTn).highType
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


end Strata.Solidity
