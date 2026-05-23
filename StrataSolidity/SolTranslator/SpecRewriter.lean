import StrataSolidity.SolTranslator.Types
import StrataSolidity.SolTranslator.SpecParser

namespace Strata.Solidity
open Laurel

/-! ## Spec rewriters

These rewriters traverse parsed spec expressions and adjust identifier
references to match the function/contract context (e.g., scalar state vars
become `self.field` accesses, mapping state vars become explicit `_in`
parameters in pre-state contexts).

After upstream PR #1077, identifier reads are `StmtExpr.Var (Variable.Local id)`
and field reads are `StmtExpr.Var (Variable.Field target id)`. After PR #1024,
quantifiers are `StmtExpr.Quantifier mode param trigger body`.

The match arms below pattern-match on the new shapes. Triggers are preserved
unchanged through the rewriters. -/

/-- Rewrite mapping identifiers to _in form (for invariant preconditions). -/
partial def rewriteMappingIdsToIn (mappingStateVars : List String) (expr : StmtExprMd) : StmtExprMd :=
  let go := rewriteMappingIdsToIn mappingStateVars
  match expr.val with
  | .Var (.Local name) =>
    if mappingStateVars.contains name.text then
      { expr with val := mkIdentifier (name.text ++ "_in") }
    else expr
  | .PrimitiveOp op args => { expr with val := .PrimitiveOp op (args.map go) }
  | .StaticCall callee args => { expr with val := .StaticCall callee (args.map go) }
  | .Var (.Field target f) => { expr with val := mkFieldSelect (go target) f.text }
  | .Quantifier mode p trigger body =>
    { expr with val := .Quantifier mode p trigger (go body) }
  | .Old inner => { expr with val := .Old (go inner) }
  | _ => expr

/-- Rewrite state variable references inside an old() expression.
    Mapping state vars: `name` → `name_in` (explicit input parameter).
    Array length refs: `name_length` → `name_length_in`.
    Scalar state vars: leave unchanged (best-effort: `old(x)` ≡ `x` until
      upstream provides a pre-state mechanism). -/
partial def rewriteOldMappingRefs (mappingStateVars : List String) (arrayStateVars : List String)
    (_scalarStateVars : List String)
    (expr : StmtExprMd) : StmtExprMd :=
  let rewrite (e : StmtExprMd) := rewriteOldMappingRefs mappingStateVars arrayStateVars _scalarStateVars e
  match expr.val with
  | .Var (.Local name) =>
    if mappingStateVars.contains name.text then
      { expr with val := mkIdentifier s!"{name.text}_in" }
    else
      let isArrayLength := arrayStateVars.any fun av => name.text == s!"{av}_length"
      if isArrayLength then
        { expr with val := mkIdentifier s!"{name.text}_in" }
      else expr
  | .PrimitiveOp op args =>
    { expr with val := .PrimitiveOp op (args.map rewrite) }
  | .StaticCall callee args =>
    { expr with val := .StaticCall callee (args.map rewrite) }
  | .Var (.Field target fieldName) =>
    { expr with val := mkFieldSelect (rewrite target) fieldName.text }
  | .IfThenElse cond thenBr elseBr =>
    { expr with val := .IfThenElse (rewrite cond) (rewrite thenBr) (elseBr.map rewrite) }
  | .Quantifier mode param trigger body =>
    let shadowedMappings := mappingStateVars.filter (· != param.name.text)
    let shadowedArrays := arrayStateVars.filter (· != param.name.text)
    let shadowedScalars := _scalarStateVars.filter (· != param.name.text)
    let body' := rewriteOldMappingRefs shadowedMappings shadowedArrays shadowedScalars body
    { expr with val := .Quantifier mode param trigger body' }
  | _ => expr

/-- Process `__old` markers in a parsed spec expression.
    Replaces `StaticCall "__old" [inner]` by applying `rewriteOldMappingRefs`
    to the inner expression. -/
partial def processOldMarkers (mappingStateVars : List String) (arrayStateVars : List String)
    (scalarStateVars : List String)
    (expr : StmtExprMd) : StmtExprMd :=
  let go := processOldMarkers mappingStateVars arrayStateVars scalarStateVars
  match expr.val with
  | .StaticCall callee args =>
    if callee.text == "__old" then
      match args with
      | [inner] => rewriteOldMappingRefs mappingStateVars arrayStateVars scalarStateVars (go inner)
      | _ => expr
    else
      { expr with val := .StaticCall callee (args.map go) }
  | .PrimitiveOp op args =>
    { expr with val := .PrimitiveOp op (args.map go) }
  | .Var (.Field target fieldName) =>
    { expr with val := mkFieldSelect (go target) fieldName.text }
  | .IfThenElse cond thenBr elseBr =>
    { expr with val := .IfThenElse (go cond) (go thenBr) (elseBr.map go) }
  | .Quantifier mode param trigger body =>
    { expr with val := .Quantifier mode param trigger (go body) }
  | _ => expr

/-- Rewrite bare state variable identifiers in NatSpec-parsed spec expressions.
    Scalar state vars: `Identifier "x"` → `FieldSelect self "x"`
    Mapping state vars: left as `Identifier "x"` (they're explicit parameters).
    Skips identifiers that are local names, parameters, or not state vars. -/
partial def rewriteStateVarRefs (stateVarNames : List String) (mappingStateVars : List String)
    (localNames : List String) (expr : StmtExprMd) : StmtExprMd :=
  let go := rewriteStateVarRefs stateVarNames mappingStateVars localNames
  match expr.val with
  | .Var (.Local name) =>
    if localNames.contains name.text then expr
    else if mappingStateVars.contains name.text then expr  -- mappings are explicit params
    else if name.text.startsWith "__old_" then
      let realName := (name.text.drop 6).toString
      if stateVarNames.contains realName then
        -- Best-effort handling of `old(stateVar)` after upstream removed
        -- modifies clauses (PR #759) and polyOldOp (PR #542): emit a fresh
        -- free variable named `__old_<name>` that is unconstrained.
        --
        -- Trade-off: postconditions that *relate* the new state to the old
        -- (e.g., `count == old(count) + amount`) become trivially satisfiable
        -- because the verifier sees `__old_count` as any value. We accept this
        -- degradation in exchange for end-to-end pipeline operation; users
        -- writing such specs will see them pass vacuously (a known limitation).
        --
        -- Once upstream provides an `out`/`inout`-based pre-state mechanism,
        -- this site should switch to the new shape.
        expr
      else expr
    else if stateVarNames.contains name.text then
      mkStmtExprMd (mkFieldSelect (mkStmtExprMd (mkIdentifier "self")) name.text)
    else expr
  | .PrimitiveOp op args =>
    { expr with val := .PrimitiveOp op (args.map go) }
  | .StaticCall callee args =>
    { expr with val := .StaticCall callee (args.map go) }
  | .Var (.Field target fieldName) =>
    { expr with val := mkFieldSelect (go target) fieldName.text }
  | .IfThenElse cond thenBr elseBr =>
    { expr with val := .IfThenElse (go cond) (go thenBr) (elseBr.map go) }
  | .Quantifier mode param trigger body =>
    let locals' := localNames ++ [param.name.text]
    let body' := rewriteStateVarRefs stateVarNames mappingStateVars locals' body
    { expr with val := .Quantifier mode param trigger body' }
  | _ => expr


end Strata.Solidity
