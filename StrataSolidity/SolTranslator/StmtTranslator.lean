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
  | .PrimitiveOp op args =>
    { expr with val := .PrimitiveOp op (args.map rewrite) }
  | .StaticCall callee args =>
    { expr with val := .StaticCall callee (args.map rewrite) }
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

/-- Translate a Solidity FunctionDefinition to a Laurel Procedure.
    Positional argument contract for non-pure functions (must match call site in translateExpr):
      [self?, msg_sender, mapping_vars..., mapping_lengths..., user_args_as_name_param...]
    where `self` is present only if there are non-mapping state variables. -/
def translateFunction (ctx : TransCtx) (fn : Solidity.node SourceRange)
    : Except TranslationError Procedure := do
  match fn with
  | .FunctionDefinition fnSr nameAnn kindAnn mutAnn _visAnn _virtualAnn params retParams bodyOpt docAnn modifiersSeq => do
    let isConstructor := kindAnn.val == "constructor"
    let funcName := if isConstructor then s!"{ctx.contractName}_ctor"
                    else if kindAnn.val == "receive" then s!"{ctx.contractName}_receive"
                    else if kindAnn.val == "fallback" then s!"{ctx.contractName}_fallback"
                    else s!"{ctx.contractName}_{nameAnn.val}"
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
                              type := mkHighTypeMd (.UserDefined (mkIdent ctx.contractName)) }]
      -- Assert non-negativity only for INTEGER scalar state vars (Solidity
      -- uints are always >= 0). Non-int fields (e.g. bool) must not get a
      -- `>= 0` precondition — that produces an ill-typed `bool >= 0`.
      for name in nonMappingStateVars do
        let isIntField := ctx.contractFields.any fun f =>
          f.name.text == name && (match f.type.val with | .TInt => true | _ => false)
        if isIntField then
          let fieldExpr := mkStmtExprMd (mkFieldSelect (mkStmtExprMd (mkIdentifier "self")) name)
          preconditions := preconditions ++ [mkStmtExprMd (.PrimitiveOp .Geq [fieldExpr, mkStmtExprMd (.LiteralInt 0)])]
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
            [mkStmtExprMd (.PrimitiveOp .Eq [selfField, inRef])]

    -- Add implicit msg_sender parameter for non-pure functions
    if !isPure then
      inputs := inputs ++ [{ name := "msg_sender", type := mkHighTypeMd .TInt }]
      preconditions := preconditions ++ [mkNonNegPrecond "msg_sender"]
      -- msg.sender is always > 0 (zero address cannot send transactions)
      preconditions := preconditions ++ [mkStmtExprMd (.PrimitiveOp .Gt [
        mkStmtExprMd (mkIdentifier "msg_sender"), mkStmtExprMd (.LiteralInt 0)])]
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
        | .VariableDeclaration _ pName typeNameOpt _ _ _ _ _ storageLocAnn _ _ =>
          let solTy := match typeNameOpt with
            | .some_type_name _ tn => translateTypeNode ctx tn
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
          | .VariableDeclaration _ pName typeNameOpt _ _ _ _ _ _ _ _ =>
            let solTy := match typeNameOpt with
              | .some_type_name _ tn => translateTypeNode ctx tn
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
    -- Parse @custom:strata annotations from NatSpec documentation
    let annotations := parseStrataAnnotations docAnn.val
    let natspecLoopInvStrs := annotations.filterMap fun
      | .loopInvariant e => some e | _ => none
    let natspecLoopInvExprs ← natspecLoopInvStrs.mapM parseSpecExpr
    -- Rewrite state var refs in loop invariants
    let specLocalNames := userParamInfo.map (·.1) ++
      (outputs.map (·.name.text)) ++ ["msg_sender", "msg_value"]
    let rewriteSVGlobal := rewriteStateVarRefs ctx.stateVarNames ctx.mappingStateVars specLocalNames
    -- Process old() markers in loop invariants BEFORE rewriting state var refs
    let natspecLoopInvExprs := natspecLoopInvExprs.map
      (processOldMarkers ctx.mappingStateVars ctx.arrayStateVars ctx.stateVarNames)
    let natspecLoopInvExprs := natspecLoopInvExprs.map rewriteSVGlobal
    let bodyCtx := { ctx with localNames := ctx.localNames ++ paramNames ++ outputNames ++ mappingOutputNames ++ arrayLengthOutputNames ++ userParamInfo.map (·.1),
                              memoryArrayParams := memoryArrayParamNames,
                              hasSelfParam := !isPure && hasNonMappingState && !isConstructor,
                              loopInvariantExprs := natspecLoopInvExprs }
    let (specPres, _specPosts, body, contractInvariants) ← match bodyOpt with
      | .some_node _ bodyNode => do
        let natspecPres := annotations.filterMap fun
          | .requires e => if hasStructAccess e then none else some e | _ => none
        let natspecPosts := annotations.filterMap fun
          | .ensures e => if hasStructAccess e then none else some e | _ => none

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
        let rewriteSV := rewriteStateVarRefs ctx.stateVarNames ctx.mappingStateVars specLocalNames
        let specPreExprs := specPreExprs.map rewriteSV
        let specPostExprs := specPostExprs.map rewriteSV

        -- Rewrite precondition expressions: user parameter names → _param names
        -- and mapping state var names → _in names (preconditions reference pre-state)
        let userParamNames := userParamInfo.map (·.1)
        let specPreExprs := specPreExprs.map (rewriteParamRefs userParamNames)
        let specPreExprs := if !isPure && !isView && !isConstructor then
          specPreExprs.map (rewriteOldMappingRefs ctx.mappingStateVars ctx.arrayStateVars ctx.stateVarNames)
        else specPreExprs
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
            -- For array state vars, also initialize length to 0
            if ctx.arrayStateVars.contains field.name.text then
              preamble := preamble ++ [mkStmtExprMd (.Assign [toAssignTarget (mkStmtExprMd (mkIdentifier s!"{field.name.text}_length"))]
                (mkStmtExprMd (.LiteralInt 0)))]
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
        let contractInvariants := if isPure || isView then []
          else if isConstructor then ctx.contractInvariantNatspec else ctx.contractInvariantNatspec.map rewriteSV
        -- Rewrite invariant expressions: user parameter names → _param names
        let contractInvariants := contractInvariants.map (rewriteParamRefs userParamNames)
        -- Generate frame conditions from @custom:strata modifies
        let natspecModifies := annotations.filterMap fun
          | .modifies vars => some vars | _ => none
        let frameConditions := if natspecModifies.isEmpty || isPure || isView || isConstructor then []
          else
            -- Parse comma-separated variable names from modifies annotation.
            -- Each entry may be "varName" or "varName[keyExpr]".
            let modifiedEntries := natspecModifies.foldl (fun acc s =>
              acc ++ ((s.splitOn ",").map fun x => (x.toSlice.trimAscii).toString)) ([] : List String)
            -- Split entries into (baseName, optionalKeyExpr) pairs
            let parseEntry (entry : String) : String × Option String :=
              match entry.splitOn "[" with
              | [base] => (base.trimAscii.toString, none)
              | [base, keyPart] => (base.trimAscii.toString, some (keyPart.dropEnd 1 |>.trimAscii.toString))  -- strip trailing ]
              | _ => (entry.trimAscii.toString, none)
            let parsedEntries := modifiedEntries.map parseEntry
            let modifiedBaseNames := parsedEntries.map (·.1)
            -- For each mapping state variable NOT in modifies list, add var == var_in
            -- For key-scoped modifies (e.g., balances[msg.sender]), add:
            --   forall __k : int :: __k != key1 && __k != key2 ==> select(var, __k) == select(var_in, __k)
            let framePosts := ctx.mappingStateVars.filterMap fun (name : String) =>
              let entries := parsedEntries.filter fun (b, _) => b == name
              if entries.isEmpty then
                -- Not in modifies list: full frame (var == var_in)
                some (mkStmtExprMd (.PrimitiveOp .Eq [
                  mkStmtExprMd (mkIdentifier name),
                  mkStmtExprMd (mkIdentifier (name ++ "_in"))]))
              else if entries.any fun (_, k) => k.isNone then
                none  -- Whole-mapping modified (at least one entry has no key), no frame
              else
                -- Collect all key expressions for this mapping
                let keyExprs := entries.filterMap fun (_, k) => k
                let parsedKeys := keyExprs.filterMap fun keyStr =>
                  match SpecParser.parseExpr (SpecParser.tokenize keyStr) with
                  | .ok (keyExpr, _) => some (rewriteParamRefs userParamNames keyExpr)
                  | .error _ => none
                if parsedKeys.isEmpty then none
                else
                  let kVar := mkStmtExprMd (mkIdentifier "__k")
                  let kParam : Parameter := { name := "__k", type := mkHighTypeMd .TInt }
                  -- __k != key1 && __k != key2 && ...
                  let neqs := parsedKeys.map fun keyExpr =>
                    mkStmtExprMd (.PrimitiveOp .Neq [kVar, keyExpr])
                  let guard := match neqs with
                    | [single] => single
                    | _ => neqs.foldl (fun acc neq =>
                        if acc.val matches .LiteralBool true then neq
                        else mkStmtExprMd (.PrimitiveOp .And [acc, neq]))
                      (mkStmtExprMd (.LiteralBool true))
                  let lhs := mkStmtExprMd (.StaticCall "select" [mkStmtExprMd (mkIdentifier name), kVar])
                  let rhs := mkStmtExprMd (.StaticCall "select" [mkStmtExprMd (mkIdentifier (name ++ "_in")), kVar])
                  let eq := mkStmtExprMd (.PrimitiveOp .Eq [lhs, rhs])
                  let body := mkStmtExprMd (.PrimitiveOp .Implies [guard, eq])
                  some (mkStmtExprMd (mkForall kParam body))
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
                some (mkStmtExprMd (.PrimitiveOp .Eq [selfField, inRef]))
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
        let specAndFramePosts := specPostExprs ++ frameConditions
        let allPosts := specAndFramePosts ++ contractInvariants
        -- Attach function source range to postconditions for SARIF location reporting
        let allPosts := allPosts.map (withSourceRange ctx fnSr)
        -- Only include self in modifies list when contract has scalar (non-mapping) state vars
        let modifiesList := if !isPure && hasNonMappingState && !isConstructor then
          [mkStmtExprMd (mkIdentifier "self")]
        else []
        let specAndFrameConds : List Condition :=
          (specAndFramePosts.map (withSourceRange ctx fnSr)).map fun p =>
            { condition := p, summary := none }
        let invariantConds : List Condition :=
          (contractInvariants.map (withSourceRange ctx fnSr)).map fun p =>
            { condition := p, summary := some "invariant" }
        let allPostsConds : List Condition := specAndFrameConds ++ invariantConds
        pure (specPreExprs, allPosts, Body.Opaque allPostsConds (some bodyExpr)
          modifiesList, contractInvariants)
      | .missing_node _ =>
        -- No body: use NatSpec invariants (rewrite state var refs)
        let specLocalNames := userParamInfo.map (·.1) ++
          (outputs.map (·.name.text)) ++ ["msg_sender", "msg_value"]
        let rewriteSV := rewriteStateVarRefs ctx.stateVarNames ctx.mappingStateVars specLocalNames
        let contractInvariants := if isPure || isView then []
          else ctx.contractInvariantNatspec.map rewriteSV
        let invariantsAsConds : List Condition :=
          contractInvariants.map fun p => { condition := p, summary := none }
        pure ([], contractInvariants, if contractInvariants.isEmpty then .Abstract []
          else .Abstract invariantsAsConds, contractInvariants)

    -- Reuse the already-translated contract invariants for preconditions.
    -- Contract invariants as preconditions apply to non-pure, non-constructor functions.
    -- (Constructors establish the invariant; they don't assume it.)
    -- Preconditions reference input state: rewrite mapping names to _in form.
    let rewriteMapNamesToIn := rewriteMappingIdsToIn ctx.mappingStateVars
    let applicableInvariantPres := if isPure || isView || isConstructor then []
      else contractInvariants.map rewriteMapNamesToIn
    -- Collect modifier preconditions: for each applied modifier, translate its
    -- pre-_ require statement nodes in this function's context and add as assumes.
    let mut modifierPres : List StmtExprMd := []
    for modNode in modifiersSeq.val do
      match modNode with
      | .ModifierInvocation _ modNameAnn _ =>
        match ctx.modifierDefs.lookup modNameAnn.val with
        | some reqNodes =>
          for reqNode in reqNodes do
            let e ← translateExpr bodyCtx reqNode
            modifierPres := modifierPres ++ [e]
        | none => pure ()
      | _ => pure ()
    -- Sum axioms: for each mapping, assume the update axiom as a precondition.
    -- forall m, k, v :: sum_<name>(update(m, k, v)) == sum_<name>(m) - select(m, k) + v
    let sumAxioms := if isPure || isView then [] else ctx.mappingStateVars.map fun name =>
      let mapType := mkHighTypeMd (.TMap (mkHighTypeMd .TInt) (mkHighTypeMd .TInt))
      let mVar := mkStmtExprMd (mkIdentifier "m")
      let kVar := mkStmtExprMd (mkIdentifier "k")
      let vVar := mkStmtExprMd (mkIdentifier "v")
      let updated := mkStmtExprMd (.StaticCall "update" [mVar, kVar, vVar])
      let sumUpdated := mkStmtExprMd (.StaticCall s!"sum_{name}" [updated])
      let sumM := mkStmtExprMd (.StaticCall s!"sum_{name}" [mVar])
      let selMK := mkStmtExprMd (.StaticCall "select" [mVar, kVar])
      let rhs := mkStmtExprMd (.PrimitiveOp .Add [
        mkStmtExprMd (.PrimitiveOp .Sub [sumM, selMK]), vVar])
      mkStmtExprMd (mkForall { name := "m", type := mapType }
        (mkStmtExprMd (mkForall { name := "k", type := mkHighTypeMd .TInt }
          (mkStmtExprMd (mkForall { name := "v", type := mkHighTypeMd .TInt }
            (mkStmtExprMd (.PrimitiveOp .Eq [sumUpdated, rhs])))))))

    let allPreconditions := preconditions ++ modifierPres ++ specPres ++ applicableInvariantPres ++ sumAxioms
    -- Deduplicate preconditions (non-negativity may overlap with invariants or user requires)
    let allPreconditions := allPreconditions.foldl (fun acc p =>
      if acc.any (fun q => toString (repr p.val) == toString (repr q.val)) then acc else acc ++ [p]) []

    -- Wrap preconditions in Condition records (new Laurel shape requires this).
    let allPreconditionConds : List Condition :=
      allPreconditions.map fun p => { condition := p, summary := none }

    return {
      name := funcName
      inputs := inputs
      outputs := outputs
      preconditions := allPreconditionConds
      decreases := none
      isFunctional := false
      body := body
    }
  | _ => throw (.internalError "Expected FunctionDefinition")


end Strata.Solidity
