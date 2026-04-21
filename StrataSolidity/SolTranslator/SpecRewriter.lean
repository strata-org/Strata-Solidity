import StrataSolidity.SolTranslator.Types
import StrataSolidity.SolTranslator.SpecParser

namespace Strata.Solidity
open Laurel

/-- Rewrite mapping identifiers to _in form (for invariant preconditions). -/
partial def rewriteMappingIdsToIn (mappingStateVars : List String) (expr : StmtExprMd) : StmtExprMd :=
  let go := rewriteMappingIdsToIn mappingStateVars
  match expr.val with
  | .Identifier name =>
    if mappingStateVars.contains name.text then
      { expr with val := .Identifier (name.text ++ "_in") }
    else expr
  | .PrimitiveOp op args => { expr with val := .PrimitiveOp op (args.map go) }
  | .StaticCall callee args => { expr with val := .StaticCall callee (args.map go) }
  | .FieldSelect target f => { expr with val := .FieldSelect (go target) f }
  | .Forall p body => { expr with val := .Forall p (go body) }
  | .Exists p body => { expr with val := .Exists p (go body) }
  | .Old inner => { expr with val := .Old (go inner) }
  | _ => expr

/-- Rewrite state variable references inside an old() expression.
    Mapping state vars: `name` → `name_in` (explicit input parameter).
    Array length refs: `name_length` → `name_length_in`.
    Scalar state vars: `name` → `__old_name` (marker for rewriteStateVarRefs). -/
partial def rewriteOldMappingRefs (mappingStateVars : List String) (arrayStateVars : List String)
    (scalarStateVars : List String)
    (expr : StmtExprMd) : StmtExprMd :=
  let rewrite (e : StmtExprMd) := rewriteOldMappingRefs mappingStateVars arrayStateVars scalarStateVars e
  match expr.val with
  | .Identifier name =>
    if mappingStateVars.contains name.text then
      { expr with val := .Identifier s!"{name.text}_in" }
    else if scalarStateVars.contains name.text then
      { expr with val := .Identifier s!"__old_{name.text}" }
    else
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
    let shadowedMappings := mappingStateVars.filter (· != param.name.text)
    let shadowedArrays := arrayStateVars.filter (· != param.name.text)
    let shadowedScalars := scalarStateVars.filter (· != param.name.text)
    { expr with val := .Forall param (rewriteOldMappingRefs shadowedMappings shadowedArrays shadowedScalars body) }
  | .Exists param body =>
    let shadowedMappings := mappingStateVars.filter (· != param.name.text)
    let shadowedArrays := arrayStateVars.filter (· != param.name.text)
    let shadowedScalars := scalarStateVars.filter (· != param.name.text)
    { expr with val := .Exists param (rewriteOldMappingRefs shadowedMappings shadowedArrays shadowedScalars body) }
  | _ => expr

/-- Process `__old` markers in a parsed spec expression.
    Replaces `StaticCall "__old" [inner]` by applying `rewriteOldMappingRefs`
    to the inner expression. -/
partial def processOldMarkers (mappingStateVars : List String) (arrayStateVars : List String)
    (scalarStateVars : List String)
    (expr : StmtExprMd) : StmtExprMd :=
  let go := processOldMarkers mappingStateVars arrayStateVars scalarStateVars
  match expr.val with
  | .StaticCall "__old" args =>
    match args with
    | [inner] => rewriteOldMappingRefs mappingStateVars arrayStateVars scalarStateVars (go inner)
    | _ => expr
  | .PrimitiveOp op args =>
    { expr with val := .PrimitiveOp op (args.map go) }
  | .StaticCall callee args =>
    { expr with val := .StaticCall callee (args.map go) }
  | .FieldSelect target fieldName =>
    { expr with val := .FieldSelect (go target) fieldName }
  | .IfThenElse cond thenBr elseBr =>
    { expr with val := .IfThenElse (go cond) (go thenBr) (elseBr.map go) }
  | .Forall param body =>
    { expr with val := .Forall param (go body) }
  | .Exists param body =>
    { expr with val := .Exists param (go body) }
  | _ => expr

/-- Rewrite bare state variable identifiers in NatSpec-parsed spec expressions.
    Scalar state vars: `Identifier "x"` → `FieldSelect self "x"`
    Mapping state vars: left as `Identifier "x"` (they're explicit parameters).
    Skips identifiers that are local names, parameters, or not state vars. -/
partial def rewriteStateVarRefs (stateVarNames : List String) (mappingStateVars : List String)
    (localNames : List String) (expr : StmtExprMd) : StmtExprMd :=
  let go := rewriteStateVarRefs stateVarNames mappingStateVars localNames
  match expr.val with
  | .Identifier name =>
    if localNames.contains name.text then expr
    else if mappingStateVars.contains name.text then expr  -- mappings are explicit params
    else if name.text.startsWith "__old_" then
      let realName : Identifier := (name.text.drop 6).toString
      if stateVarNames.contains realName.text then
        mkStmtExprMd (.Old (mkStmtExprMd (.FieldSelect (mkStmtExprMd (.Identifier "self")) realName)))
      else expr
    else if stateVarNames.contains name.text then
      mkStmtExprMd (.FieldSelect (mkStmtExprMd (.Identifier "self")) name)
    else expr
  | .PrimitiveOp op args =>
    { expr with val := .PrimitiveOp op (args.map go) }
  | .StaticCall callee args =>
    { expr with val := .StaticCall callee (args.map go) }
  | .FieldSelect target fieldName =>
    { expr with val := .FieldSelect (go target) fieldName }
  | .IfThenElse cond thenBr elseBr =>
    { expr with val := .IfThenElse (go cond) (go thenBr) (elseBr.map go) }
  | .Forall param body =>
    let locals' := localNames ++ [param.name.text]
    { expr with val := .Forall param (rewriteStateVarRefs stateVarNames mappingStateVars locals' body) }
  | .Exists param body =>
    let locals' := localNames ++ [param.name.text]
    { expr with val := .Exists param (rewriteStateVarRefs stateVarNames mappingStateVars locals' body) }
  | _ => expr


end Strata.Solidity
