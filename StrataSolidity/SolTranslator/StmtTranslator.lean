/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

import StrataSolidity.SolTranslator.Types
import StrataSolidity.SolTranslator.SpecParser
import StrataSolidity.SolTranslator.SpecRewriter
import StrataSolidity.SolTranslator.ExprTranslator

namespace Strata.Solidity
open Laurel


/-! ## Function Translation -/

/-- Rewrite identifiers in a StmtExprMd: replace user parameter names with their
    `_param` suffixed versions for use in postconditions. Postconditions reference
    the original (immutable) input values, which are named `name_param` in Core. -/
partial def rewriteParamRefs (paramNames : List String) (expr : StmtExprMd) : StmtExprMd :=
  let rewrite (e : StmtExprMd) := rewriteParamRefs paramNames e
  match expr.val with
  | .Var (.Local name) =>
    if paramNames.contains name.text then
      { expr with val := mkIdentifier s!"{name.text}_param" }
    else expr
  | .StaticCall callee args tys =>
    { expr with val := .StaticCall callee (args.map rewrite) tys }
  | .Old value =>
    { expr with val := .Old (rewrite value) }
  | .Var (.Field target fieldName) =>
    { expr with val := mkFieldSelect (rewrite target) fieldName.text }
  | .IfThenElse cond thenBr elseBr =>
    { expr with val := .IfThenElse (rewrite cond) (rewrite thenBr) (elseBr.map rewrite) }
  | .Quantifier .Forall param _ body =>
    -- Don't rewrite the bound variable if it shadows a parameter name
    let shadowed := paramNames.filter (· != param.name.text)
    { expr with val := mkForall param (rewriteParamRefs shadowed body) }
  | .Quantifier .Exists param _ body =>
    let shadowed := paramNames.filter (· != param.name.text)
    { expr with val := mkExists param (rewriteParamRefs shadowed body) }
  | _ => expr

/-- Resolve contract invariants for one function. Invariants are about
    contract state, so they are resolved with no locals in scope: a
    parameter or named return that shadows a state variable must not
    capture the invariant (it would turn into an assumption about an
    argument). Constructors read and write state through their output
    parameters, which carry the state variables' names, so only named
    constants are folded there. -/
def resolveInvariants (ctx : TransCtx) (isConstructor : Bool) (invs : List StmtExprMd)
    : List StmtExprMd :=
  if isConstructor then
    invs.map (rewriteStateVarRefs [] [] [] · ctx.constantDefs)
  else
    invs.map (rewriteStateVarRefs ctx.stateVarNames ctx.mappingStateVars [] · ctx.constantDefs)

/-- Translate a Solidity FunctionDefinition to a Laurel Procedure.
    Inputs, in order (internal call sites must match, see
    `translateInternalCall`): `self` and `<scalar>_in` for each scalar state
    variable (non-pure functions of contracts with scalar state, not
    constructors), `msg_sender` and `msg_value` (non-pure), each mapping or
    array state variable (`<m>_in`, or `<m>` for view functions) with its
    `_length` (non-pure, not constructors), then `<p>_param` for each user
    parameter, followed by `<p>_length` for memory arrays. Outputs: the
    declared returns, then the post-state of each mapping and array state
    variable (mutating functions) or of every state variable (constructors). -/
def translateFunction (ctx : TransCtx) (fn : Solidity.node SourceRange)
    : Except TranslationError Procedure := do
  match fn with
  | .FunctionDefinition fnSr nameAnn kindAnn mutAnn visAnn _virtualAnn params retParams bodyOpt docAnn modifiersSeq => do
    let isConstructor := kindAnn.val == "constructor"
    let funcName := if isConstructor then s!"{ctx.contractName}_ctor"
                    else if kindAnn.val == "receive" then s!"{ctx.contractName}_receive"
                    else if kindAnn.val == "fallback" then s!"{ctx.contractName}_fallback"
                    else s!"{ctx.contractName}_{nameAnn.val}"
    let isPure := mutAnn.val == "pure"
    let isView := mutAnn.val == "view"
    -- Contract invariants hold between transactions, i.e. at external entry
    -- points: public and external functions, receive and fallback assume
    -- them on entry (constructors establish them instead) and re-establish
    -- them on exit (view functions cannot change state). Internal and
    -- private helpers run in the middle of an entry point, where an
    -- invariant may be temporarily broken, so they neither assume nor
    -- re-establish it; the calling entry point checks it on exit.
    let isEntryPoint := visAnn.val == "public" || visAnn.val == "external" ||
      kindAnn.val == "receive" || kindAnn.val == "fallback"
    let checksInvariants := !isPure && !isView && (isConstructor || isEntryPoint)

    -- Translate parameters, tracking Solidity types for bounds
    let mut inputs : List Parameter := []
    let mut preconditions : List StmtExprMd := []
    -- Facts the Solidity type system guarantees (value ranges). They are
    -- assumed by the procedure but not checked at internal call sites:
    -- the model does not bound intermediate arithmetic (overflow reverts
    -- in Solidity), so a call site could not prove them, and every value
    -- that reaches a call in a real execution satisfies them.
    let mut typeRanges : List (StmtExprMd × String) := []

    -- Add implicit self parameter for non-pure functions with contract state
    -- Only add self for non-mapping state vars (mapping vars are separate params)
    let nonMappingStateVars := ctx.stateVarNames.filter (!ctx.mappingStateVars.contains ·)
    let hasNonMappingState := !nonMappingStateVars.isEmpty
    if !isPure && hasNonMappingState && !isConstructor then
      inputs := inputs ++ [{ name := "self",
                              type := mkHighTypeMd (.UserDefined (mkIdent ctx.contractName)) }]
      -- Scalar state variables hold values of their Solidity type: uintN in
      -- [0, 2^N), intN in [-2^(N-1), 2^(N-1)), address in [0, 2^160), ….
      -- (Only for typed integer-like fields: `bool >= 0` would be ill-typed,
      -- and a signed field must not be assumed non-negative.)
      for name in nonMappingStateVars do
        if let some solName := ctx.fieldSolTypes.lookup name then
          let fieldExpr := mkStmtExprMd (mkFieldSelect (mkStmtExprMd (mkIdentifier "self")) name)
          if let some c := mkRangeCond solName fieldExpr then
            typeRanges := typeRanges ++ [(c, s!"type range of {name} ({solName})")]
      -- Synthetic pre-state input parameters for scalar state vars.
      -- For each scalar field, add `<name>_in : <type>` and a precondition
      -- `self.<name> == <name>_in` so that `<name>_in` carries the pre-state
      -- value of the field. Spec rewriter resolves `old(<name>)` to
      -- `<name>_in` (see SpecRewriter.rewriteStateVarRefs).
      for field in ctx.contractFields do
        if !ctx.mappingStateVars.contains field.name.text then
          let inName := s!"{field.name.text}_in"
          inputs := inputs ++ [{ name := inName, type := field.type }]
          let selfField := mkStmtExprMd
            (mkFieldSelect (mkStmtExprMd (mkIdentifier "self")) field.name.text)
          let inRef := mkStmtExprMd (mkIdentifier inName)
          preconditions := preconditions ++
            [mkStmtExprMd (mkPrimOp .Eq [selfField, inRef])]

    -- Add implicit msg_sender parameter for non-pure functions
    if !isPure then
      inputs := inputs ++ [{ name := "msg_sender", type := mkHighTypeMd .TInt }]
      if let some c := mkRangeCond "address" (mkStmtExprMd (mkIdentifier "msg_sender")) then
        typeRanges := typeRanges ++ [(c, "type range of msg.sender (address)")]
      -- msg.sender is always > 0 (zero address cannot send transactions)
      preconditions := preconditions ++ [mkStmtExprMd (mkPrimOp .Gt [
        mkStmtExprMd (mkIdentifier "msg_sender"), mkStmtExprMd (.LiteralInt 0)])]
      inputs := inputs ++ [{ name := "msg_value", type := mkHighTypeMd .TInt }]
      if let some c := mkRangeCond "uint256" (mkStmtExprMd (mkIdentifier "msg_value")) then
        typeRanges := typeRanges ++ [(c, "type range of msg.value (uint256)")]

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
            -- A fixed-size array always has its declared length.
            if let some n := ctx.fixedArrayLengths.lookup field.name.text then
              typeRanges := typeRanges ++ [(mkStmtExprMd (mkPrimOp .Eq
                [mkStmtExprMd (mkIdentifier lenName), mkStmtExprMd (.LiteralInt n)]),
                s!"length of {field.name.text} ({n})")]

    -- Track memory array parameters for paired length params
    let mut memoryArrayParamNames : List String := []
    -- Track user-provided parameter names and types for local copy generation.
    -- In Solidity, function parameters are mutable local copies; in Laurel/Core,
    -- input parameters are immutable. We rename inputs to `name_param` and create
    -- local variables `name := name_param` at the start of the body.
    let mut userParamInfo : List (String × HighTypeMd) := []
    -- Parameters in memory or calldata (see `TransCtx.memoryVars`).
    let mut memoryParams : List (String × HighTypeMd) := []

    match params with
    | .ParameterList _ paramsSeq =>
      let mut anonIdx := 0
      for param in paramsSeq.val do
        match param with
        | .VariableDeclaration _ pName typeNameOpt _ _ _ _ _ storageLocAnn _ _ =>
          let solTy := match typeNameOpt with
            | .some_type_name _ tn => translateTypeNode ctx tn
            | .missing_type_name _ => { highType := mkHighTypeMd .TInt, solName := "uint256" }
          -- Unnamed parameters (`function f(address, int24)`) are legal
          -- Solidity; synthesize a unique name per position so the `_param`
          -- inputs (and their local copies) don't collide.
          let baseName ← if pName.val.isEmpty then do
              let n := anonIdx
              anonIdx := anonIdx + 1
              pure s!"__arg{n}"
            else pure pName.val
          -- Rename user parameter to `name_param` so we can create a mutable local copy
          let inputName := s!"{baseName}_param"
          inputs := inputs ++ [{ name := inputName, type := solTy.highType }]
          userParamInfo := userParamInfo ++ [(baseName, solTy.highType)]
          -- The argument is a value of its Solidity type.
          if let some c := mkRangeCond solTy.solName (mkStmtExprMd (mkIdentifier inputName)) then
            typeRanges := typeRanges ++ [(c, s!"type range of {baseName} ({solTy.solName})")]
          if storageLocAnn.val == "memory" || storageLocAnn.val == "calldata" then
            memoryParams := memoryParams ++ [(baseName, solTy.highType)]
          -- For memory array parameters, add a paired length parameter,
          -- copied to a local like the array (inline assembly can change it)
          if solTy.solName == "array" &&
             (storageLocAnn.val == "memory" || storageLocAnn.val == "calldata") then
            let lenName := s!"{baseName}_length"
            inputs := inputs ++ [{ name := s!"{lenName}_param", type := mkHighTypeMd .TInt }]
            userParamInfo := userParamInfo ++ [(lenName, mkHighTypeMd .TInt)]
            preconditions := preconditions ++ [mkNonNegPrecond s!"{lenName}_param"]
            memoryArrayParamNames := memoryArrayParamNames ++ [baseName]
        | _ => throw (.unsupported "Non-VariableDeclaration in parameter list")
    | _ => throw (.internalError "Expected ParameterList for parameters")

    -- Translate return parameters. Unnamed returns get position-unique
    -- names (`result`, `result1`, ...) so multi-value unnamed returns
    -- (`returns (uint256, uint256)`) don't collide.
    let baseOutputs ← match retParams with
      | .ParameterList _ retSeq =>
        retSeq.val.toList.zipIdx.mapM fun (param, i) =>
          match param with
          | .VariableDeclaration _ pName typeNameOpt _ _ _ _ _ _ _ _ =>
            let solTy := match typeNameOpt with
              | .some_type_name _ tn => translateTypeNode ctx tn
              | .missing_type_name _ => { highType := mkHighTypeMd .TInt, solName := "uint256" }
            let outName := if pName.val.isEmpty then
                (if i == 0 then "result" else s!"result{i}")
              else pName.val
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
    -- Parse @custom:strata annotations from NatSpec documentation
    -- Each annotation is paired with the source range of its NatSpec line,
    -- so every clause's obligations report that line.
    let annotationsAt := parseStrataAnnotationsAt ctx.source docAnn
    let annotations := annotationsAt.map (·.1)
    let natspecLoopInvs := annotationsAt.filterMap fun
      | (.loopInvariant e, r) => some (e, r) | _ => none
    let natspecLoopInvExprs ← natspecLoopInvs.mapM fun (e, _) => parseSpecExpr e
    -- Rewrite state var refs in loop invariants
    let specLocalNames := userParamInfo.map (·.1) ++
      (outputs.map (·.name.text)) ++ ["msg_sender", "msg_value"]
    let rewriteSVGlobal := fun e =>
      rewriteStateVarRefs ctx.stateVarNames ctx.mappingStateVars specLocalNames e ctx.constantDefs
    -- Process old() markers in loop invariants BEFORE rewriting state var refs
    let natspecLoopInvExprs := natspecLoopInvExprs.map
      (processOldMarkers ctx.mappingStateVars ctx.arrayStateVars ctx.stateVarNames)
    let natspecLoopInvExprs := natspecLoopInvExprs.map rewriteSVGlobal
    -- Located after rewriting: a rewrite may rebuild the root node.
    let natspecLoopInvExprs := (natspecLoopInvExprs.zip natspecLoopInvs).map fun (e, (_, r)) =>
      withSourceRangeDeep ctx r (withSourceRange ctx r e)
    -- Valued-return desugaring: when the procedure ends up with MULTIPLE
    -- output parameters (a declared return value plus mapping-state
    -- outputs), Laurel's EliminateValueReturns rejects `return e`. Record
    -- the declared return's output name so translateStmt desugars
    -- `return e` into `<name> := e; return`.
    let valuedReturnTarget :=
      if outputs.length > 1 && !isConstructor then
        baseOutputs.head?.map (·.name.text)
      else none
    let bodyCtx := { ctx with localNames := ctx.localNames ++ paramNames ++ outputNames ++ mappingOutputNames ++ arrayLengthOutputNames ++ userParamInfo.map (·.1),
                              memoryArrayParams := memoryArrayParamNames,
                              hasSelfParam := !isPure && hasNonMappingState && !isConstructor,
                              mayWriteState := !isPure && !isView,
                              isConstructor := isConstructor,
                              returnNames := baseOutputs.map (·.name.text),
                              memoryVars := memoryParams,
                              valuedReturnTarget := valuedReturnTarget,
                              loopInvariantExprs := natspecLoopInvExprs }
    let (specPres, _specPosts, body, contractInvariants) ← match bodyOpt with
      | .some_node _ bodyNode => do
        let natspecPresAt := annotationsAt.filterMap fun
          | (.requires e, r) => if hasStructAccess e then none else some (e, r) | _ => none
        let natspecPostsAt := annotationsAt.filterMap fun
          | (.ensures e, r) => if hasStructAccess e then none else some (e, r) | _ => none
        let natspecPres := natspecPresAt.map (·.1)
        let natspecPosts := natspecPostsAt.map (·.1)

        -- Parse NatSpec spec expressions
        let specPreExprs ← natspecPres.mapM parseSpecExpr
        let specPostExprs ← natspecPosts.mapM fun s => do
          let expr ← parseSpecExpr s
          pure (processOldMarkers ctx.mappingStateVars ctx.arrayStateVars ctx.stateVarNames expr)

        -- Rewrite bare state variable identifiers to FieldSelect self "name"
        -- for scalar state vars. Mapping state vars stay as bare Identifier.
        -- Parameter names and output names are treated as locals (not rewritten).
        let specLocalNames := userParamInfo.map (·.1) ++
          (outputs.map (·.name.text)) ++ ["msg_sender", "msg_value"]
        let rewriteSV := fun e =>
          rewriteStateVarRefs ctx.stateVarNames ctx.mappingStateVars specLocalNames e ctx.constantDefs
        let specPreExprs := specPreExprs.map rewriteSV
        let specPostExprs := specPostExprs.map rewriteSV

        -- Rewrite precondition expressions: user parameter names → _param names
        -- and mapping state var names → _in names (preconditions reference pre-state)
        let userParamNames := userParamInfo.map (·.1)
        let specPreExprs := specPreExprs.map (rewriteParamRefs userParamNames)
        let specPreExprs := if !isPure && !isView && !isConstructor then
          specPreExprs.map (rewriteOldMappingRefs ctx.mappingStateVars ctx.arrayStateVars ctx.stateVarNames)
        else specPreExprs
        let specPreExprs := (specPreExprs.zip natspecPresAt).map fun (e, (_, r)) =>
          withSourceRangeDeep ctx r (withSourceRange ctx r e)
        -- Rewrite postcondition expressions: user parameter names → _param names
        let specPostExprs := specPostExprs.map (rewriteParamRefs userParamNames)
        -- Translate body statements
        let bodyStmts ← match bodyNode with
          | .Block _ stmtsSeq => translateBlockStmts bodyCtx stmtsSeq.val.toList
          | _ => pure [← translateStmt bodyCtx bodyNode]
        let b := mkStmtExprMd (.Block bodyStmts none)
        -- Build preamble: local copies of user params + mapping init assigns
        let mut preamble : List StmtExprMd := []
        -- 1. Local copies of user-provided parameters (Solidity params are mutable)
        for (name, ty) in userParamInfo do
          preamble := preamble ++ [mkStmtExprMd (mkLocalVar name ty
            (some (mkStmtExprMd (mkIdentifier s!"{name}_param"))))]
        -- 2. Constructor default storage initialization (Solidity zero-inits all state)
        if isConstructor then
          for field in ctx.contractFields do
            let defaultVal := defaultValueForType field.type
            preamble := preamble ++ [mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier field.name.text))]
              defaultVal)]
            -- For array state vars, also initialize the length: 0, or the
            -- declared length of a fixed-size array
            if ctx.arrayStateVars.contains field.name.text then
              let len := (ctx.fixedArrayLengths.lookup field.name.text).getD 0
              preamble := preamble ++ [mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier s!"{field.name.text}_length"))]
                (mkStmtExprMd (.LiteralInt len)))]
          -- 2b. State-variable initializers (`uint256 x = 1000;`), in
          -- declaration order, before the body. One the translator cannot
          -- express gives the variable an unknown value (a sound
          -- over-approximation) instead of failing the whole file: one it
          -- cannot translate, a string or `bytes` value (modelled as an
          -- integer, so `"Token"` would not type-check), or one reading
          -- `this`. An array's length is that of an inline array literal,
          -- unknown for other initializers.
          let fresh := mkStmtExprMd (.Hole (deterministic := false))
          for (name, initNode) in ctx.stateVarInits do
            let opaqueType := ["string", "bytes"].contains ((ctx.fieldSolTypes.lookup name).getD "")
            let value := match translateExpr bodyCtx initNode with
              | .ok v =>
                if opaqueType || anyStmtExpr (fun e => match e.val with
                    | .LiteralString _ => true
                    | .Var (.Local id) => id.text == "this"
                    | _ => false) v then fresh
                else v
              | .error _ => fresh
            preamble := preamble ++
              [mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier name))] value)]
            if ctx.arrayStateVars.contains name then
              let len := match initNode with
                | .InlineArrayExpression _ elems => mkStmtExprMd (.LiteralInt elems.val.size)
                | _ => fresh
              preamble := preamble ++
                [mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier s!"{name}_length"))] len)]
        -- 3. Mapping state var init assigns (name := name_in)
        if !isPure && !isView && !isConstructor && !ctx.mappingStateVars.isEmpty then
          for name in ctx.mappingStateVars do
            preamble := preamble ++ [mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier name))]
              (mkStmtExprMd (mkIdentifier s!"{name}_in")))]
            if ctx.arrayStateVars.contains name then
              preamble := preamble ++ [mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier s!"{name}_length"))]
                (mkStmtExprMd (mkIdentifier s!"{name}_length_in")))]
        let bodyExpr := if preamble.isEmpty then b
          else mkStmtExprMd (.Block (preamble ++ [b]) none)
        -- Translate contract invariant nodes once in this function's body context,
        -- then reuse for both pre- and postconditions. This avoids redundant
        -- effectful translation and prevents divergence if translateExpr gains
        -- side effects (e.g., fresh name generation).
        -- Contract invariants only apply to non-pure, non-view functions (and constructors
        -- for postconditions only). View functions cannot modify state, so they need not
        -- re-establish the invariant.
        let contractInvariants := if !checksInvariants then [] else
          resolveInvariants ctx isConstructor ctx.contractInvariantNatspec
        -- Generate frame conditions from @custom:strata modifies
        let natspecModifies := annotations.filterMap fun
          | .modifies vars => some vars | _ => none
        let frameConditions := if natspecModifies.isEmpty || isPure || isView || isConstructor then []
          else
            let parsedEntries := natspecModifies.flatMap SpecParser.modifiesEntries
            let modifiedBaseNames := parsedEntries.map (·.1)
            -- For each mapping state variable NOT in modifies list, add var == var_in
            -- For key-scoped modifies (e.g., balances[msg.sender]), add:
            --   forall __k : int :: __k != key1 && __k != key2 ==> select(var, __k) == select(var_in, __k)
            let framePosts := ctx.mappingStateVars.filterMap fun (name : String) =>
              let entries := parsedEntries.filter fun (b, _) => b == name
              if entries.isEmpty then
                -- Not in modifies list: full frame (var == var_in)
                some (name, mkStmtExprMd (mkPrimOp .Eq [
                  mkStmtExprMd (mkIdentifier name),
                  mkStmtExprMd (mkIdentifier (name ++ "_in"))]))
              else if entries.any fun (_, k) => k.isNone then
                none  -- Whole-mapping modified (at least one entry has no key), no frame
              else
                -- Collect all key expressions for this mapping
                let keyExprs := entries.filterMap fun (_, k) => k
                -- A key that cannot be read leaves the mapping unframed (the
                -- caller warns about it).
                let parsedKeys := keyExprs.filterMap fun keyStr =>
                  match SpecParser.parseExpr (SpecParser.tokenize keyStr) with
                  | .ok (keyExpr, []) =>
                    -- Fold constant state vars (e.g. `modifies roles[DEFAULT_ADMIN_ROLE]`)
                    -- and resolve scalar state vars in key position; then rename
                    -- user params to their `_param` form.
                    let keyExpr := rewriteStateVarRefs ctx.stateVarNames ctx.mappingStateVars
                      (userParamInfo.map (·.1) ++ ["msg_sender", "msg_value"]) keyExpr ctx.constantDefs
                    some (rewriteParamRefs userParamNames keyExpr)
                  | _ => none
                if parsedKeys.length != keyExprs.length then none
                else
                  let kVar := mkStmtExprMd (mkIdentifier "__k")
                  let kParam : Parameter := { name := "__k", type := mkHighTypeMd .TInt }
                  -- __k != key1 && __k != key2 && ...
                  let neqs := parsedKeys.map fun keyExpr =>
                    mkStmtExprMd (mkPrimOp .Neq [kVar, keyExpr])
                  let guard := match neqs with
                    | [single] => single
                    | _ => neqs.foldl (fun acc neq =>
                        if acc.val matches .LiteralBool true then neq
                        else mkStmtExprMd (mkPrimOp .And [acc, neq]))
                      (mkStmtExprMd (.LiteralBool true))
                  let lhs := mkStmtExprMd (mkCall "select" [mkStmtExprMd (mkIdentifier name), kVar])
                  let rhs := mkStmtExprMd (mkCall "select" [mkStmtExprMd (mkIdentifier (name ++ "_in")), kVar])
                  let eq := mkStmtExprMd (mkPrimOp .Eq [lhs, rhs])
                  let body := mkStmtExprMd (mkPrimOp .Implies [guard, eq])
                  some (name, mkStmtExprMd (mkForall kParam body))
            -- Bug fix: also generate frame conditions for scalar state vars not in modifies.
            -- Scalar vars are heap-allocated, but the heap frame only excludes other objects,
            -- not other fields of self. We need explicit field-level framing.
            let scalarFramePosts := ctx.stateVarNames.filterMap fun name =>
              if ctx.mappingStateVars.contains name then none  -- handled above
              else if modifiedBaseNames.contains name then none  -- declared as modified
              else
                -- scalar not modified: self#name == <name>_in
                -- The pre-state value lives in the synthetic <name>_in input
                -- parameter (added by this same function above), pinned to
                -- self.<name> at entry. This avoids emitting a .Old AST node
                -- which the upstream Laurel→Core translator does not handle.
                let selfField := mkStmtExprMd
                  (mkFieldSelect (mkStmtExprMd (mkIdentifier "self")) name)
                let inRef := mkStmtExprMd (mkIdentifier s!"{name}_in")
                some (name, mkStmtExprMd (mkPrimOp .Eq [selfField, inRef]))
            framePosts ++ scalarFramePosts
        -- Always emit Body.Opaque. Upstream PR #1076 (Various Laurel resolver
        -- improvements) disallows Body.Transparent procedures with the error
        -- "transparent procedures are not yet supported. Add 'opaque' to make
        -- the procedure opaque". When there are no postconditions, we still
        -- use Body.Opaque with an empty postconds list — semantically a
        -- procedure with no observable effect, which is what spec-less
        -- functions deserve.
        -- Contract invariants are emitted as plain postcondition expressions
        -- and tagged via the Condition `summary` field (the designed labeling
        -- channel — it flows to Core's propertySummary metadata and the SARIF
        -- `strata/invariant-fail` classifier keys off the substring
        -- "invariant"). A previous attempt wrapped each invariant in a
        -- synthetic `StaticCall "__strata_invariant" [inv]` "for label
        -- generation", but the obligation label is derived from the
        -- translateChecks labelBase ("postcondition_N"), NOT from the
        -- expression — so the wrapper never affected any label and instead
        -- reached Laurel→Core as a call to an undeclared function, failing
        -- with "Resolution failed: '__strata_invariant' is not defined" for
        -- every contract carrying an in-contract invariant (ERC20,
        -- Initializable, ReentrancyGuard, ...).
        let allPosts := specPostExprs ++ frameConditions.map (·.2) ++ contractInvariants
        -- Attach function source range to postconditions for SARIF location reporting
        let allPosts := allPosts.map (withSourceRange ctx fnSr)
        -- Only include self in modifies list when contract has scalar (non-mapping) state vars
        let modifiesList := if !isPure && hasNonMappingState && !isConstructor then
          [mkStmtExprMd (mkIdentifier "self")]
        else []
        -- Every postcondition carries a distinct summary. Core merges VC
        -- results that share (summary, source range), and all postconditions
        -- of a function share the function's range, so without distinct
        -- summaries every `ensures` of a function would collapse into one
        -- reported obligation.
        let mkPost (sr : SourceRange) (summary : String) (p : StmtExprMd) : Condition :=
          { condition := withSourceRangeDeep ctx sr (withSourceRange ctx sr p),
            summary := some summary }
        let specConds := (specPostExprs.zip natspecPostsAt).map fun (p, (src, r)) =>
          mkPost r s!"ensures {src}" p
        let frameConds := frameConditions.map fun (name, p) =>
          mkPost fnSr s!"modifies frame ({name})" p
        let invariantConds := contractInvariants.zipIdx.map fun (p, i) =>
          mkPost fnSr s!"invariant {ctx.contractInvariantTexts.getD i s!"#{i + 1}"}" p
        let allPostsConds : List Condition := specConds ++ frameConds ++ invariantConds
        -- One unguarded frame group. An empty target list means "changes
        -- nothing" (`ModifiesGroup.nothingChanges`); Laurel reads an empty
        -- *group* list as unframed, so the group must always be present.
        let specPreExprs := specPreExprs.zip (natspecPres.map (s!"requires {·}"))
        pure (specPreExprs, allPosts, Body.Opaque allPostsConds (some bodyExpr)
          [{ targets := modifiesList }], contractInvariants)
      | .missing_node _ =>
        -- No body: use NatSpec invariants (rewrite state var refs)
        let contractInvariants := if !checksInvariants then [] else
          resolveInvariants ctx isConstructor ctx.contractInvariantNatspec
        let invariantsAsConds : List Condition :=
          contractInvariants.map fun p => { condition := p, summary := none }
        pure ([], contractInvariants, if contractInvariants.isEmpty then .Abstract []
          else .Abstract invariantsAsConds, contractInvariants)

    -- Contract invariants as preconditions (see `isEntryPoint`). They
    -- reference the input state: mapping names are rewritten to `_in` form.
    let rewriteMapNamesToIn := (rewriteMappingIdsToIn ctx.mappingStateVars · ctx.arrayStateVars)
    let applicableInvariantPres :=
      if isPure || isConstructor || !isEntryPoint then []
      -- View functions read mappings through their plain names (no `_in`).
      else if isView then resolveInvariants ctx false ctx.contractInvariantNatspec
      else contractInvariants.map rewriteMapNamesToIn
    -- Collect modifier preconditions: for each applied modifier, translate its
    -- pre-_ require statement nodes in this function's context and add as assumes.
    -- The modifier's parameters are bound to the invocation's arguments.
    -- Like the function's own preconditions, these refer to its inputs
    -- (`x_param`, `m_in`).
    let mut modifierPres : List StmtExprMd := []
    for modNode in modifiersSeq.val do
      match modNode with
      | .ModifierInvocation _ modNameAnn argsSeq =>
        match ctx.modifierDefs.lookup modNameAnn.val with
        | some (params, reqNodes) =>
          let args ← argsSeq.val.toList.mapM (translateExpr bodyCtx)
          if args.length != params.length then
            throw (.typeError s!"modifier `{modNameAnn.val}` takes {params.length} argument(s), given {args.length}")
          let modCtx := { bodyCtx with localNames := bodyCtx.localNames ++ params }
          let binding := params.zip args
          for reqNode in reqNodes do
            let e ← translateExpr modCtx reqNode
            let e := mapStmtExpr (fun n => match n.val with
              | .Var (.Local id) => (binding.lookup id.text).getD n
              | _ => n) e
            let e := rewriteParamRefs (userParamInfo.map (·.1)) e
            let e := if !isPure && !isView && !isConstructor then rewriteMapNamesToIn e else e
            modifierPres := modifierPres ++ [e]
        | none => pure ()
      | _ => pure ()
    -- Sum axioms: for each mapping, assume the update axiom as a precondition.
    -- forall m, k, v :: sum_<name>(update(m, k, v)) == sum_<name>(m) - select(m, k) + v
    let sumAxioms := if isPure || isView then [] else
      (ctx.mappingStateVars.filter ctx.summedMappings.contains).map fun name =>
      let mapType := mkHighTypeMd (.TMap (mkHighTypeMd .TInt) (mkHighTypeMd .TInt))
      let mVar := mkStmtExprMd (mkIdentifier "m")
      let kVar := mkStmtExprMd (mkIdentifier "k")
      let vVar := mkStmtExprMd (mkIdentifier "v")
      let updated := mkStmtExprMd (mkCall "update" [mVar, kVar, vVar])
      let sumUpdated := mkStmtExprMd (mkCall s!"sum_{name}" [updated])
      let sumM := mkStmtExprMd (mkCall s!"sum_{name}" [mVar])
      let selMK := mkStmtExprMd (mkCall "select" [mVar, kVar])
      let rhs := mkStmtExprMd (mkPrimOp .Add [
        mkStmtExprMd (mkPrimOp .Sub [sumM, selMK]), vVar])
      mkStmtExprMd (mkForall { name := "m", type := mapType }
        (mkStmtExprMd (mkForall { name := "k", type := mkHighTypeMd .TInt }
          (mkStmtExprMd (mkForall { name := "v", type := mkHighTypeMd .TInt }
            (mkStmtExprMd (mkPrimOp .Eq [sumUpdated, rhs])))))))

    -- A constructor starts from empty mappings, whose sum is zero; without
    -- this, no constructor could establish a `sum(...)` invariant.
    let sumEmptyAxioms := if !isConstructor then [] else
      (ctx.mappingStateVars.filter ctx.summedMappings.contains).map fun name =>
        mkStmtExprMd (mkPrimOp .Eq [
          mkStmtExprMd (mkCall s!"sum_{name}" [mkStmtExprMd (mkCall "mapConst" [mkStmtExprMd (.LiteralInt 0)])]),
          mkStmtExprMd (.LiteralInt 0)])

    -- Every precondition gets a distinct summary. Laurel names the check
    -- it emits at each call site after the callee's precondition, and Core
    -- merges results that share (summary, location): without summaries all
    -- checks at one call site would collapse into a single "precondition".
    let described (what : String) (ps : List StmtExprMd) : List (StmtExprMd × String) :=
      ps.map fun p => (p, s!"{what} {Std.format p}")
    let allPreconditions :=
      described "precondition" preconditions ++ described "modifier precondition" modifierPres ++
      specPres ++ described "invariant" applicableInvariantPres ++
      described "axiom" (sumAxioms ++ sumEmptyAxioms)
    -- Deduplicate preconditions (non-negativity may overlap with invariants or user requires)
    let allPreconditions := allPreconditions.foldl (fun acc (p, d) =>
      if acc.any (fun (q, _) => toString (repr p.val) == toString (repr q.val)) then acc
      else acc ++ [(p, d)]) []

    -- Wrap preconditions in Condition records (new Laurel shape requires this).
    let allPreconditionConds : List Condition :=
      allPreconditions.map (fun (p, d) => { condition := p, summary := some d }) ++
      typeRanges.map fun (p, d) => { condition := p, summary := some d, mode := .Assume }

    return {
      name := funcName
      inputs := inputs
      outputs := outputs
      preconditions := allPreconditionConds
      decreases := none
      body := body
    }
  | _ => throw (.internalError "Expected FunctionDefinition")


end Strata.Solidity
