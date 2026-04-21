import StrataSolidity.SolTranslator.Types
import StrataSolidity.SolTranslator.SpecParser
import StrataSolidity.SolTranslator.SpecRewriter
import StrataSolidity.SolTranslator.ExprTranslator
import StrataSolidity.SolTranslator.StmtTranslator

namespace Strata.Solidity
open Laurel

/-! ## Contract Translation -/

/-- Translate a VariableDeclaration to a Laurel Field.
    Shared helper for struct members and state variables.
    Reads the `constant` annotation to set `isMutable` correctly. -/
def translateFieldDecl (ctx : TransCtx) (errCtx : String) (member : Solidity.node SourceRange)
    : Except TranslationError Field := do
  match member with
  | .VariableDeclaration _ nameAnn typeNameOpt _ constAnn _ _ _ =>
    let solTy ← match typeNameOpt with
      | .some_type_name _ tn => pure (translateTypeNode ctx tn)
      | .missing_type_name _ => throw (.internalError s!"{errCtx} missing type name")
    return { name := nameAnn.val, isMutable := constAnn.val != "true", type := solTy.highType }
  | _ => throw (.internalError s!"Expected VariableDeclaration for {errCtx}")

/-- Extract require condition expressions from a modifier body's pre-`_;` statements.
    Walks the Block statements until a PlaceholderStatement (serialized as
    a Literal "_") is found, collecting the first argument of require() calls. -/
private def extractModifierRequires (stmts : List (Solidity.node SourceRange))
    : List (Solidity.node SourceRange) :=
  -- Take statements before the placeholder `_;`
  let preStmts := stmts.takeWhile fun stmt =>
    match stmt with
    | .ExpressionStatement _ (.Literal _ valAnn _) => valAnn.val != "_"
    | _ => true
  -- Extract require condition arguments
  preStmts.filterMap fun stmt =>
    match stmt with
    | .ExpressionStatement _ (.FunctionCall _ (.Identifier _ nameAnn) argsSeq _ _) =>
      if nameAnn.val == "require" then argsSeq.val.toList.head? else none
    | _ => none

/-- Translate a Solidity ContractDefinition to Laurel types and procedures.
    Contracts become a CompositeType with state variables as fields;
    functions are emitted as static procedures.
    Two-pass: first collect struct definitions (for field order), then translate functions. -/
def translateContract (ctx : TransCtx) (contract : Solidity.node SourceRange)
    : Except TranslationError (List Procedure × List TypeDefinition) := do
  match contract with
  | .ContractDefinition _ nameAnn _kindAnn nodesSeq contractDocAnn _baseContracts => do
    let mut procedures : List Procedure := []
    let mut fields : List Field := []
    let mut types : List TypeDefinition := []
    let mut structFieldMap : List (String × List (String × HighType)) := ctx.structFields
    let mut enumDefs : List (String × List String) := ctx.enumDefs
    let mut stateVarInvariants : List StrataAnnotation := []
    let mut constantDefs : List (String × StmtExprMd) := []

    -- Pass 1: collect struct definitions and state variables
    for member in nodesSeq.val do
      match member with
      | .StructDefinition _ sNameAnn membersSeq => do
        let sFields ← membersSeq.val.toList.mapM (translateFieldDecl { ctx with enumDefs } "struct member")
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
      | .VariableDeclaration _ nameAnn _ stateVarAnn constAnn _ valueOpt docAnn =>
        if stateVarAnn.val == "true" then do
          -- Collect @custom:strata invariant from state variable NatSpec
          let varAnnotations := parseStrataAnnotations docAnn.val
          for ann in varAnnotations do
            match ann with
            | .invariant _ => stateVarInvariants := stateVarInvariants ++ [ann]
            | _ => pure ()
          if constAnn.val == "true" then
            -- Constant state variable: record name→value for constant folding
            match valueOpt with
            | .some_node _ valNode =>
              let valExpr ← translateExpr { ctx with enumDefs } valNode
              constantDefs := constantDefs ++ [(nameAnn.val, valExpr)]
            | _ => pure ()  -- constant without value (shouldn't happen)
          else
            let field ← translateFieldDecl { ctx with enumDefs } "state variable" member
            fields := fields ++ [field]
        else
          pure ()
      | .EnumDefinition _ eNameAnn eMembersSeq =>
        let memberNames := eMembersSeq.val.toList.filterMap fun
          | .EnumValue _ nameAnn => some nameAnn.val
          | _ => none
        enumDefs := enumDefs ++ [(eNameAnn.val, memberNames)]
      | _ => pure ()

    -- Pass 1b: collect modifier definitions (extract pre-_ require statement nodes)
    let mut modifierRequireNodes : List (String × List (Solidity.node SourceRange)) := []
    for member in nodesSeq.val do
      match member with
      | .ModifierDefinition _ modNameAnn _ bodyOpt =>
        let reqStmts := match bodyOpt with
          | .some_node _ (.Block _ stmtsSeq) =>
            extractModifierRequires stmtsSeq.val.toList
          | _ => []
        modifierRequireNodes := modifierRequireNodes ++ [(modNameAnn.val, reqStmts)]
      | _ => pure ()

    -- Pass 2: collect non-pure function names for internal call resolution
    -- Only include public/internal functions; external functions cannot be called internally.
    let stateVarNames := fields.map (·.name.text)
    -- Identify mapping-typed state variables (these bypass the heap)
    -- Collect struct names for filtering struct-valued mappings
    let structNames := structFieldMap.map (·.1)
    -- Exclude struct-valued mappings entirely (unsupported in Core HeapParameterization)
    let structMappingNames := fields.filterMap fun f =>
      match f.type.val with
      | .TMap _ valTy => match valTy.val with
        | .UserDefined name => if structNames.contains name.text then some f.name.text else none
        | _ => none
      | _ => none
    let activeFields := fields.filter fun f => !structMappingNames.contains f.name.text
    let activeStateVarNames := stateVarNames.filter fun n => !structMappingNames.contains n
    let mappingStateVars := activeFields.filterMap fun f =>
      match f.type.val with
      | .TMap _ valTy =>
        -- Exclude mappings whose value type is a struct (unsupported in Core)
        match valTy.val with
        | .UserDefined name => if structNames.contains name.text then none else some f.name.text
        | _ => some f.name.text
      | _ => none
    -- Identify array-typed state variables (subset of mappingStateVars).
    -- We re-scan the DDM nodes to distinguish ArrayTypeName from MappingType,
    -- since both translate to TMap in HighType.
    let mut arrayStateVars : List String := []
    for member in nodesSeq.val do
      match member with
      | .VariableDeclaration _ nameAnn typeNameOpt stateVarAnn _ _ _ _ =>
        if stateVarAnn.val == "true" then
          match typeNameOpt with
          | .some_type_name _ (.ArrayTypeName _ _) =>
            arrayStateVars := arrayStateVars ++ [nameAnn.val]
          | _ => pure ()
      | _ => pure ()
    let mut nonPureFunctions : List String := []
    for member in nodesSeq.val do
      match member with
      | .FunctionDefinition _ fnNameAnn fnKindAnn fnMutAnn fnVisAnn _ _ _ _ _ =>
        let fnIsPure := fnMutAnn.val == "pure"
        let fnIsConstructor := fnKindAnn.val == "constructor"
        let fnIsExternal := fnVisAnn.val == "external"
        if !fnIsPure && !fnIsConstructor && !fnIsExternal then
          nonPureFunctions := nonPureFunctions ++ [fnNameAnn.val]
      | _ => pure ()

    -- Pass 3: Parse contract invariants from NatSpec and set up function context
    let sfm := structFieldMap
    let baseFnCtx : TransCtx :=
      { ctx with structFields := sfm
                 contractName := nameAnn.val
                 contractFields := activeFields
                 stateVarNames := activeStateVarNames
                 mappingStateVars := mappingStateVars
                 arrayStateVars := arrayStateVars
                 nonPureFunctions := nonPureFunctions
                 enumDefs := enumDefs
                 constantDefs := constantDefs }
    -- Collect @custom:strata invariant only from state variable NatSpec (inside the contract).
    -- Contract-level NatSpec (above the contract keyword) is intentionally ignored
    -- to avoid ambiguity in files with multiple contracts.
    let natspecInvariantStrs := stateVarInvariants.filterMap fun
      | .invariant e => some e | _ => none
    let natspecInvariantExprs ← natspecInvariantStrs.mapM parseSpecExpr

    -- Pass 4: translate functions with struct field info, state context, and invariant nodes
    -- Invariant nodes are re-translated per function so that state variable references
    -- resolve correctly in each function's context.
    let fnCtx := { baseFnCtx with contractInvariantNatspec := natspecInvariantExprs,
                                   modifierDefs := modifierRequireNodes }
    for member in nodesSeq.val do
      match member with
      | .FunctionDefinition _ fnNameAnn _ _ _ _ _ bodyOpt _ _ => do
          -- Skip functions that reference struct-valued mappings (unsupported in Core)
          let bodyText := match bodyOpt with
            | .some_node _ _ => toString (repr bodyOpt)
            | _ => ""
          let usesStructMapping := structMappingNames.any fun name => (bodyText.splitOn name).length > 1
          if usesStructMapping then pure ()
          else do
            let proc ← translateFunction fnCtx member
            procedures := procedures ++ [proc]
      | _ => pure ()

    -- Contract invariants are checked via injection into public functions'
    -- pre/postconditions. No separate invariant procedure is needed.

    -- Emit a CompositeType for the contract only when it has non-mapping state-variable fields.
    -- Mapping fields are passed as explicit parameters, not stored on the heap.
    let nonMappingFields := activeFields.filter fun f => !mappingStateVars.contains f.name.text
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
      | .ContractDefinition _ _ _ _ _ _ => do
        let (procs, types) ← translateContract ctx node
        allProcedures := allProcedures ++ procs
        allTypes := allTypes ++ types
      | .PragmaDirective _ _ => pure ()  -- Skip pragmas
      | _ => pure ()  -- Skip unsupported top-level nodes

    -- Collect all mapping state variable names from procedure parameters.
    -- Mapping state vars appear as "<name>_in : Map[int, ...]" input parameters.
    let allMappingNames := allProcedures.foldl (fun acc proc =>
      acc ++ (proc.inputs.filterMap fun param =>
        if param.name.text.endsWith "_in" then
          match param.type.val with
          | .TMap _ _ => some (param.name.text.dropRight 3)  -- strip "_in"
          | _ => none
        else none)) ([] : List String)
    let allMappingNames := allMappingNames.eraseDups

    -- Declare uninterpreted functions used by the translator.
    -- These are abstract procedures with no body, giving the solver
    -- functional consistency (same inputs → same output) but no other axioms.
    let mkUninterpBinary (name : String) : Procedure := {
      name := name
      inputs := [{ name := "a", type := mkHighTypeMd .TInt },
                 { name := "b", type := mkHighTypeMd .TInt }]
      outputs := [{ name := "result", type := mkHighTypeMd .TInt }]
      preconditions := []
      determinism := .deterministic none
      decreases := none
      isFunctional := true
      body := .Abstract []
      md := default
    }
    let mkUninterpUnary (name : String) : Procedure := {
      name := name
      inputs := [{ name := "a", type := mkHighTypeMd .TInt }]
      outputs := [{ name := "result", type := mkHighTypeMd .TInt }]
      preconditions := []
      determinism := .deterministic none
      decreases := none
      isFunctional := true
      body := .Abstract []
      md := default
    }
    let uninterpFunctions := [
      mkUninterpBinary "bit_and", mkUninterpBinary "bit_or",
      mkUninterpBinary "bit_xor", mkUninterpBinary "bit_shl",
      mkUninterpBinary "bit_shr", mkUninterpUnary "bit_not",
      mkUninterpUnary "keccak256", mkUninterpUnary "sha256",
      mkUninterpUnary "abi_encode", mkUninterpBinary "abi_encode2",
      mkUninterpUnary "abi_encodePacked", mkUninterpBinary "abi_encodePacked2",
      mkUninterpUnary "abi_encodeWithSelector",
      mkUninterpUnary "abi_encodeWithSignature",
      mkUninterpUnary "abi_decode",
      mkUninterpUnary "address_balance",
      mkUninterpUnary "address_code", mkUninterpUnary "address_codehash"
    ]

    -- Declare sum() for each mapping state variable that appears in a sum() call in specs.
    -- sum : Map[int, int] → int, with update axiom:
    --   forall m : Map[int,int], k : int, v : int ::
    --     sum(update(m, k, v)) == sum(m) - select(m, k) + v
    -- Also: sum(const(0)) == 0  (empty mapping has zero sum)
    let sumFunctions := allMappingNames.filterMap fun name =>
      if true then  -- declare sum for all mappings; unused ones don't affect z3
        let mapType := mkHighTypeMd (.TMap (mkHighTypeMd .TInt) (mkHighTypeMd .TInt))
        let mVar := mkStmtExprMd (.Identifier "m")
        let kVar := mkStmtExprMd (.Identifier "k")
        let vVar := mkStmtExprMd (.Identifier "v")
        -- sum(update(m, k, v)) == sum(m) - select(m, k) + v
        let updated := mkStmtExprMd (.StaticCall "update" [mVar, kVar, vVar])
        let sumUpdated := mkStmtExprMd (.StaticCall s!"sum_{name}" [updated])
        let sumM := mkStmtExprMd (.StaticCall s!"sum_{name}" [mVar])
        let selMK := mkStmtExprMd (.StaticCall "select" [mVar, kVar])
        let rhs := mkStmtExprMd (.PrimitiveOp .Add [
          mkStmtExprMd (.PrimitiveOp .Sub [sumM, selMK]), vVar])
        let updateAxiom := mkStmtExprMd (.Forall
          { name := "m", type := mapType }
          (mkStmtExprMd (.Forall
            { name := "k", type := mkHighTypeMd .TInt }
            (mkStmtExprMd (.Forall
              { name := "v", type := mkHighTypeMd .TInt }
              (mkStmtExprMd (.PrimitiveOp .Eq [sumUpdated, rhs])))))))
        -- sum(const(0)) == 0
        let emptyMap := mkStmtExprMd (.StaticCall "const" [mkStmtExprMd (.LiteralInt 0)])
        let sumEmpty := mkStmtExprMd (.StaticCall s!"sum_{name}" [emptyMap])
        let emptyAxiom := mkStmtExprMd (.PrimitiveOp .Eq [sumEmpty, mkStmtExprMd (.LiteralInt 0)])
        some {
          name := s!"sum_{name}"
          inputs := [{ name := "m", type := mapType }]
          outputs := [{ name := "result", type := mkHighTypeMd .TInt }]
          preconditions := []
          determinism := .deterministic none
          decreases := none
          isFunctional := true
          body := .Abstract [updateAxiom, emptyAxiom]
          md := default
        }
      else none

    return {
      staticProcedures := uninterpFunctions ++ sumFunctions ++ allProcedures
      staticFields := []
      types := allTypes
      constants := []
    }

end Strata.Solidity

