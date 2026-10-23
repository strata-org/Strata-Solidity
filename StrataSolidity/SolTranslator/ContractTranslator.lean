/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

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
  | .VariableDeclaration _ nameAnn typeNameOpt _ constAnn _ _ _ _ _ _ =>
    let solTy ← match typeNameOpt with
      | .some_type_name _ tn => pure (translateTypeNode ctx tn)
      | .missing_type_name _ => throw (.internalError s!"{errCtx} missing type name")
    return { name := nameAnn.val, isMutable := constAnn.val != "true", type := solTy.highType }
  | _ => throw (.internalError s!"Expected VariableDeclaration for {errCtx}")

/-- Warnings for `@custom:strata` lines in `doc` that are not verified:
    unrecognized keywords, recognized ones that have no effect on the
    declaration `doc` is attached to (`allowed` lists the keywords that do;
    `reason` explains why a keyword has no effect, if it can), and text on
    the lines after an annotation, which NatSpec treats as part of it but the
    translator does not read. -/
private def annotationWarnings (source? : Option String) (declDesc : String)
    (allowed : List String) (doc : StrataDDM.Ann String SourceRange)
    (reason : String → Option String := fun _ => none) : List TranslationWarning :=
  let lines := strataAnnotationLinesAt source? doc
  let unrecognized := (unrecognizedStrataAnnotationsAt source? doc).map fun (line, r) =>
    { range := r, message :=
        if line.isEmpty then
          s!"`@custom:strata` with no annotation on the same line ({declDesc}) is ignored: " ++
            "each annotation must fit on one line"
        else s!"unrecognized annotation `@custom:strata {line}` on {declDesc} is ignored" }
  let misplaced := (parseStrataAnnotationsAt source? doc).filterMap fun (ann, r) =>
    if allowed.contains ann.keyword then none
    else
      let why := match reason ann.keyword with
        | some w => s!": {w}"
        | none => " and is ignored"
      some { range := r, message := s!"`@custom:strata {ann.keyword}` has no effect on {declDesc}{why}" }
  let continued := (continuedStrataAnnotations doc.val).filterMap fun i =>
    (lines[i]?.filter (!·.1.isEmpty)).map fun (line, r) =>
      { range := r, message :=
          s!"the text on the line after `@custom:strata {line}` is ignored: " ++
          "each annotation must fit on one line" }
  unrecognized ++ misplaced ++ continued

/-- Names `m` of every `sum(m)` in the annotations of a NatSpec comment. -/
private def summedNames (doc : String) : List String :=
  (strataAnnotationLines doc).flatMap fun line =>
    let toks := SpecParser.tokenize line
    (toks.zip (toks.drop 1 |>.zip (toks.drop 2 |>.zip (toks.drop 3)))).filterMap
      fun (t0, t1, t2, t3) => if t0 == "sum" && t1 == "(" && t3 == ")" then some t2 else none

/-- How warnings name a function. solc gives `receive` and `fallback` an
    empty name. -/
private def functionDesc (kind name : String) : String :=
  match kind with
  | "constructor" => "the constructor"
  | "receive" => "the receive function"
  | "fallback" => "the fallback function"
  | _ => s!"function `{name}`"

/-- Whether the `repr` of an AST has an `Identifier` node `name` (not a
    string literal, member name or declared name that happens to read
    `name`). An identifier renders as `node.Identifier <range> { …, val :=
    "<name>" }`. -/
private def reprMentions (astRepr name : String) : Bool :=
  (astRepr.splitOn "Strata.Solidity.node.Identifier").drop 1 |>.any fun chunk =>
    (chunk.startsWith " " || chunk.startsWith "\n") &&
    match (chunk.splitOn "val := \"").drop 1 |>.head? with
    | some rest => (rest.splitOn "\"").head? == some name
    | none => false

/-- Whether the `repr` of an AST contains a loop statement. -/
private def reprHasLoop (astRepr : String) : Bool :=
  ["ForStatement", "WhileStatement", "DoWhileStatement"].any fun c =>
    (astRepr.splitOn s!"Strata.Solidity.node.{c}").length > 1

/-! ## Inheritance

solc does not flatten inherited members: a `ContractDefinition` lists only
the members written in it, and names its direct bases in `baseContracts`.
A contract is therefore verified as the flattening of its bases and
itself, so that inherited state, functions, modifiers and invariants
resolve in the derived contract's own context (its `self`, its state
parameters). Each contract of the file is still verified on its own too.
-/

/-- A contract's name, kind, members, documentation and direct bases. -/
private structure ContractInfo where
  name : String
  kind : String
  members : List (Solidity.node SourceRange)
  doc : StrataDDM.Ann String SourceRange
  bases : List String

private def contractInfo? : Solidity.node SourceRange → Option ContractInfo
  | .ContractDefinition _ nameAnn kindAnn _ nodesSeq docAnn baseContracts =>
    some { name := nameAnn.val, kind := kindAnn.val, members := nodesSeq.val.toList,
           doc := docAnn, bases := baseContracts.val.toList.map (·.val) }
  | _ => none

/-- Whether a member is a constructor. -/
private def isConstructorMember : Solidity.node SourceRange → Bool
  | .FunctionDefinition _ _ k .. => k.val == "constructor"
  | _ => false

/-- The C3 merge of `seqs`: repeatedly the first head that is in no tail.
    `none` if there is none (the hierarchy cannot be linearized). -/
private def c3Merge (seqs : List (List String)) : Option (List String) :=
  go seqs (seqs.foldl (· + ·.length) 1)
where
  go (seqs : List (List String)) : Nat → Option (List String)
    | 0 => none
    | fuel + 1 =>
      let seqs := seqs.filter (!·.isEmpty)
      if seqs.isEmpty then some [] else
      let inTail (c : String) := seqs.any fun s => (s.drop 1).contains c
      match seqs.findSome? fun s => s.head?.filter (!inTail ·) with
      | none => none
      | some c => (go (seqs.map fun s => if s.head? == some c then s.drop 1 else s) fuel).map (c :: ·)

/-- The C3 linearization of `name`, most derived first, as solc computes
    it (`linearizedBaseContracts`): for `contract C is B1, …, Bn`,
    `L(C) = C :: merge(L(Bn), …, L(B1), [Bn, …, B1])` (Solidity lists the
    bases most base-like first, the reverse of Python). A base the file does
    not define is a leaf: its own bases are unknown. `none` if the bases
    cannot be linearized, which solc rejects. -/
private partial def linearize (ctx : TransCtx) (name : String) : Option (List String) :=
  match (ctx.contractNodes.lookup name).bind contractInfo? with
  | none => some [name]
  | some info => do
    let direct := info.bases.reverse
    let merged ← c3Merge ((← direct.mapM (linearize ctx)) ++ [direct])
    return name :: merged

/-- solc's type of a parameter, without its data location (`uint256`,
    `struct C.Info`), which an override may change (`calldata` to
    `memory`). -/
private def paramTypeKey (ctx : TransCtx) : Solidity.node SourceRange → String
  | .VariableDeclaration sr .. =>
    let ts := (ctx.typeAt? sr "VariableDeclaration").getD "?"
    let locations := [" storage ref", " storage pointer", " storage", " memory", " calldata"]
    match locations.find? (fun (l : String) => ts.endsWith l) with
    | some l => (ts.dropEnd l.length).toString
    | none => ts
  | _ => "?"

/-- What a derived definition overrides. A function is keyed by its name
    and parameter types: an overload with other parameters is a different
    function. `receive` and `fallback` are keyed by kind, constructors by
    nothing (a base constructor is not a procedure of the derived contract;
    it runs as part of deployment). -/
private def overrideKey (ctx : TransCtx) : Solidity.node SourceRange → Option String
  | .FunctionDefinition _ nameAnn kindAnn _ _ _ params .. =>
    if kindAnn.val == "constructor" then none
    else if kindAnn.val == "function" then
      let types := match params with
        | .ParameterList _ ps => ps.val.toList.map (paramTypeKey ctx)
        | _ => []
      some s!"fn {nameAnn.val}({",".intercalate types})"
    else some kindAnn.val
  | .ModifierDefinition _ nameAnn .. => some s!"mod {nameAnn.val}"
  | _ => none

/-- The name under which the implementation of `fname` written in `owner`
    is emitted when a more derived contract overrides it and a call
    reaches it (`super.fname(…)`, `owner.fname(…)`): an internal procedure
    of the contract being verified. -/
private def inheritedImplName (owner fname : String) : String :=
  s!"__base_{owner}_{fname}"

/-- A function definition renamed `name`, with internal visibility: how an
    overridden implementation is emitted, reachable only from the calls
    that name it. -/
private def asInheritedImpl (name : String) : Solidity.node SourceRange → Option (Solidity.node SourceRange)
  | .FunctionDefinition sr nameAnn kindAnn mutAnn _visAnn virtAnn params rets body doc mods =>
    some (.FunctionDefinition sr { nameAnn with val := name } kindAnn mutAnn
      { nameAnn with val := "internal" } virtAnn params rets body doc mods)
  | _ => none

/-- Translate a Solidity ContractDefinition to Laurel types and procedures.
    Contracts become a CompositeType with state variables as fields;
    functions are emitted as static procedures.
    Two-pass: first collect struct definitions (for field order), then translate functions.
    Also returns a warning for every annotation or function that is not verified. -/
def translateContract (ctx : TransCtx) (contract : Solidity.node SourceRange)
    : Except TranslationError (List Procedure × List TypeDefinition × List TranslationWarning) := do
  match contract with
  | .ContractDefinition contractSr nameAnn kindAnn _abstractAnn nodesSeq contractDocAnn _ => do
    let mut warnings : List TranslationWarning := []
    let mut procedures : List Procedure := []
    let mut fields : List Field := []
    let mut types : List TypeDefinition := []
    let mut structFieldMap : List (String × List (String × HighType)) := ctx.structFields
    let mut enumDefs : List (String × List String) := ctx.enumDefs
    let mut udvtNames : List String := ctx.udvtNames

    -- The bases this contract inherits from, most-base-first (the reverse
    -- of the C3 linearization), and every member to verify it with: the
    -- bases' members (except their constructors, which are not procedures
    -- of this contract) followed by its own, each tagged with the contract
    -- that defines it. A definition a more derived contract repeats
    -- (`override`) replaces the inherited one.
    let some linearization := linearize ctx nameAnn.val
      | throw (.unsupported s!"the bases of `{nameAnn.val}` cannot be linearized")
    let bases := (linearization.drop 1).reverse.filterMap fun b =>
      (ctx.contractNodes.lookup b).bind contractInfo?
    let ownMembers := nodesSeq.val.toList
    -- A base this file does not define (an imported one, or one an imported
    -- base inherits) contributes no members, so what it declares does not
    -- resolve here, and its functions are entry points that are not checked.
    for b in linearization.drop 1 do
      if !(ctx.contractNodes.any (·.1 == b)) then
        warnings := warnings ++ [{ range := contractSr, message :=
          s!"base contract `{b}` of `{nameAnn.val}` is not defined in this file: its state, functions and invariants are not part of what is verified here" }]
    let taggedAll : List (String × Solidity.node SourceRange) :=
      bases.flatMap (fun b => (b.members.filter (!isConstructorMember ·)).map ((b.name, ·))) ++
        ownMembers.map ((nameAnn.val, ·))
    -- A public state variable overrides the base function its getter
    -- implements (solc allows the shared name only then).
    let publicVarNames := taggedAll.filterMap fun (_, m) => match m with
      | .VariableDeclaration _ n _ sv _ _ vis .. =>
        if sv.val == "true" && vis.val == "public" then some n.val else none
      | _ => none
    let taggedMembers := taggedAll.zipIdx.filterMap fun ((owner, m), i) =>
      match overrideKey ctx m, m with
      | some k, .FunctionDefinition _ fnName kind .. =>
        if (taggedAll.drop (i + 1)).any (overrideKey ctx ·.2 == some k) then none
        else if kind.val == "function" && publicVarNames.contains fnName.val then none
        else some (owner, m)
      | some k, _ =>
        if (taggedAll.drop (i + 1)).any (overrideKey ctx ·.2 == some k) then none
        else some (owner, m)
      | none, _ => some (owner, m)
    -- State variables of the same name in different contracts (a base's
    -- private one and a derived one) are different variables: not
    -- modelled. (Overloads, functions of the same name with different
    -- parameters, are distinct procedures, as in a single contract.)
    let varOwners := taggedMembers.filterMap fun (owner, m) => match m with
      | .VariableDeclaration _ n _ sv .. => if sv.val == "true" then some (n.val, owner) else none
      | _ => none
    if let some (v, o) := varOwners.find? fun (v, o) => varOwners.any fun (v', o') => v' == v && o' != o then
      let others := varOwners.filterMap fun (v', o') => if v' == v && o' != o then some s!"`{o'}`" else none
      throw (.unsupported s!"the state variable `{v}` of `{o}`, declared again in {", ".intercalate others}: they are different variables")
    -- Members this contract declares itself. Everything inherited is
    -- reported where it is written, when its own contract is verified, so
    -- only these produce warnings here.
    let isOwn (owner : String) : Bool := owner == nameAnn.val

    -- `super.f(…)` in code written in contract `cn` calls the implementation
    -- of `f` that follows `cn` in the linearization, and `X.f(…)` (for a
    -- base `X`) the first one in X's own linearization. One that a more
    -- derived contract overrides is emitted, when a call reaches it, as the
    -- internal procedure `__base_<owner>_<f>`.
    let membersOf (cn : String) : List (Solidity.node SourceRange) :=
      (((ctx.contractNodes.lookup cn).bind contractInfo?).map (·.members)).getD []
    let fnImpl (fname : String) : Solidity.node SourceRange → Bool
      | .FunctionDefinition _ n k _ _ _ _ _ body _ _ =>
        k.val == "function" && n.val == fname && !(body matches .missing_node _)
      | _ => false
    let implsIn (order : List String) (fname : String) : List (String × Solidity.node SourceRange) :=
      order.flatMap fun cn => (membersOf cn).filterMap fun m => if fnImpl fname m then some (cn, m) else none
    -- What a call of the implementation of `fname` in `owner` is: the
    -- procedure itself when it is the one this contract keeps.
    let implCallee (owner fname : String) : String :=
      if taggedMembers.any fun (o, m) => o == owner && fnImpl fname m then fname
      else inheritedImplName owner fname
    -- The callee of a call of `fname` resolved along `order`, or why there
    -- is none to call: `!overloaded` (calls of an overloaded function by
    -- `super` are not resolved), `!none`.
    let resolveIn (order : List String) (fname : String) : String :=
      let impls := implsIn order fname
      let keys := (impls.filterMap fun (_, m) => overrideKey ctx m).eraseDups
      if keys.length > 1 then "!overloaded"
      else match impls.head? with
        | some (owner, _) => implCallee owner fname
        | none => "!none"
    let fnNamesIn (order : List String) : List String :=
      (order.flatMap fun cn => (membersOf cn).filterMap fun
        | .FunctionDefinition _ n k .. => if k.val == "function" then some n.val else none
        | _ => none).eraseDups
    let superImplsFrom (cn : String) : List (String × String) :=
      let after := (linearization.dropWhile (· != cn)).drop 1
      (fnNamesIn after).map fun f => (f, resolveIn after f)
    let explicitImpls : List ((String × String) × String) :=
      (linearization.filter fun x => ctx.contractNodes.any (·.1 == x)).flatMap fun x =>
        let order := (linearize ctx x).getD [x]
        (fnNamesIn order).map fun f => ((x, f), resolveIn order f)
    -- Every overridden implementation a call may reach, for its signature.
    let overriddenImpls : List (String × String × Solidity.node SourceRange) :=
      (fnNamesIn linearization).flatMap fun f =>
        (implsIn linearization f).filterMap fun (owner, m) =>
          if implCallee owner f == f then none else some (owner, f, m)

    -- Contract invariants may be attached to the contract itself or to any
    -- of its state variables; solc attaches each NatSpec block to one
    -- declaration, so there is no ambiguity between contracts in a file.
    -- Interfaces and libraries have no state to keep invariant. A base's
    -- invariants constrain the state this contract inherits, so they are
    -- checked here too (the state-variable ones come with the merged
    -- members below).
    let isContract := kindAnn.val == "contract"
    let mut stateVarInvariants : List StrataAnnotation :=
      (bases.filter (·.kind == "contract")).flatMap (fun b =>
        (parseStrataAnnotations b.doc.val).filter (·.keyword == "invariant")) ++
      (if isContract then
        (parseStrataAnnotations contractDocAnn.val).filter (·.keyword == "invariant")
      else [])
    warnings := warnings ++ annotationWarnings ctx.source s!"{kindAnn.val} `{nameAnn.val}`"
      (if isContract then ["invariant"] else []) contractDocAnn
      (fun _ => if isContract then none else
        some s!"{if kindAnn.val == "interface" then "an" else "a"} {kindAnn.val} has no state, so it is ignored")
    let mut constantDefs : List (String × StmtExprMd) := []
    let mut fieldSolTypes : List (String × String) := []
    let mut stateVarInits : List (String × Solidity.node SourceRange) := []
    let mut immutableNames : List String := []

    -- Pass 1: collect struct definitions and state variables
    for (owner, member) in taggedMembers do
      match member with
      | .StructDefinition _ sNameAnn membersSeq => do
        let sFields ← membersSeq.val.toList.mapM (translateFieldDecl { ctx with enumDefs } "struct member")
        -- An inherited struct is declared and constructed by the contract
        -- that defines it; here it only has to resolve.
        if isOwn owner then
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
          { name := "__ctor_result", type := mkHighTypeMd (.UserDefined (mkIdent sNameAnn.val)) }
        let postconds := sFields.map fun f =>
          let resultField := mkStmtExprMd (mkFieldSelect
            (mkStmtExprMd (mkIdentifier "__ctor_result")) f.name.text)
          let paramRef := mkStmtExprMd (mkIdentifier f.name.text)
          mkStmtExprMd (mkPrimOp .Eq [resultField, paramRef])
        let postcondsAsConds : List Condition :=
          postconds.map fun p => { condition := p, summary := none }
        if isOwn owner then
          procedures := procedures ++ [{
            name := s!"{sNameAnn.val}_constructor"
            inputs := ctorInputs
            outputs := [ctorOutput]
            preconditions := []
            decreases := none
            body := .Abstract postcondsAsConds
          }]
      | .VariableDeclaration _ nameAnn typeNameOpt stateVarAnn constAnn mutAnn _ _ _ valueOpt docAnn =>
        if stateVarAnn.val == "true" then do
          if mutAnn.val == "immutable" then immutableNames := immutableNames ++ [nameAnn.val]
          -- Collect @custom:strata invariant from state variable NatSpec
          -- (a library's constants are not contract state)
          if isOwn owner then
            warnings := warnings ++ annotationWarnings ctx.source
              s!"state variable `{nameAnn.val}`" (if isContract then ["invariant"] else []) docAnn
              (fun _ => if isContract then none else some s!"a {kindAnn.val} has no state, so it is ignored")
          if isContract then
            for ann in parseStrataAnnotations docAnn.val do
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
            if let .some_type_name _ tn := typeNameOpt then
              fieldSolTypes := fieldSolTypes ++ [(nameAnn.val, (translateTypeNode { ctx with enumDefs } tn).solName)]
            if let .some_node _ valNode := valueOpt then
              stateVarInits := stateVarInits ++ [(nameAnn.val, valNode)]
        else
          pure ()
      | .EnumDefinition _ eNameAnn eMembersSeq =>
        let memberNames := eMembersSeq.val.toList.filterMap fun
          | .EnumValue _ nameAnn => some nameAnn.val
          | _ => none
        enumDefs := enumDefs ++ [(eNameAnn.val, memberNames)]
      | .UserDefinedValueTypeDefinition _ udvtNameAnn _ =>
        udvtNames := udvtNames ++ [udvtNameAnn.val]
      | _ => pure ()

    -- Pass 1b: collect modifier definitions (extract pre-_ require statement nodes)
    -- Modifiers, inlined into the functions that use them.
    let mut modifierDefs : List (String × List (String × HighTypeMd) × List (Solidity.node SourceRange)) := []
    let mut modifierSuperImpls : List (String × List (String × String)) := []
    for (owner, member) in taggedMembers do
      match member with
      | .ModifierDefinition _ modNameAnn paramsNode bodyOpt =>
        modifierSuperImpls := modifierSuperImpls ++ [(modNameAnn.val, superImplsFrom owner)]
        let stmts := match bodyOpt with
          | .some_node _ (.Block _ stmtsSeq) => stmtsSeq.val.toList
          | _ => []
        let params := match paramsNode with
          | .ParameterList _ ps => ps.val.toList.filterMap fun
            | .VariableDeclaration _ n (.some_type_name _ tn) .. =>
              some (n.val, (translateTypeNode { ctx with enumDefs, udvtNames } tn).highType)
            | .VariableDeclaration _ n .. => some (n.val, mkHighTypeMd .TInt)
            | _ => none
          | _ => []
        modifierDefs := modifierDefs ++ [(modNameAnn.val, params, stmts)]
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
    let mut fixedArrayLengths : List (String × Nat) := []
    for (_, member) in taggedMembers do
      match member with
      | .VariableDeclaration _ nameAnn typeNameOpt stateVarAnn _ _ _ _ _ _ _ =>
        if stateVarAnn.val == "true" then
          match typeNameOpt with
          | .some_type_name _ (.ArrayTypeName _ _ lengthAnn) =>
            arrayStateVars := arrayStateVars ++ [nameAnn.val]
            if let some n := lengthAnn.val.toNat? then
              fixedArrayLengths := fixedArrayLengths ++ [(nameAnn.val, n)]
          | _ => pure ()
      | _ => pure ()
    let mut nonPureFunctions : List String := []
    let mut functionSigs : List (String × FnSig) := []
    -- The overridden implementations a call may reach are internal
    -- procedures of this contract, so they need signatures too.
    let sigMembers : List (Solidity.node SourceRange) :=
      taggedMembers.map (·.2) ++ overriddenImpls.filterMap fun (owner, f, m) =>
        asInheritedImpl (inheritedImplName owner f) m
    for member in sigMembers do
      match member with
      | .FunctionDefinition _ fnNameAnn fnKindAnn fnMutAnn fnVisAnn _ params retParams _ _ _ =>
        let fnIsPure := fnMutAnn.val == "pure"
        let fnIsConstructor := fnKindAnn.val == "constructor"
        let fnIsExternal := fnVisAnn.val == "external"
        if !fnIsPure && !fnIsConstructor && !fnIsExternal then
          nonPureFunctions := nonPureFunctions ++ [fnNameAnn.val]
        if !fnIsConstructor && !fnIsExternal then
          let tctx := { ctx with enumDefs, udvtNames }
          let decls : Solidity.node SourceRange → List (Solidity.node SourceRange)
            | .ParameterList _ seq => seq.val.toList
            | _ => []
          let memArrayParams := (decls params).map fun
            | .VariableDeclaration _ _ (.some_type_name _ tn) _ _ _ _ _ storageLoc _ _ =>
              (translateTypeNode tctx tn).solName == "array" &&
                (storageLoc.val == "memory" || storageLoc.val == "calldata")
            | _ => false
          let returnTypes := (decls retParams).map fun
            | .VariableDeclaration _ _ (.some_type_name _ tn) _ _ _ _ _ _ _ _ =>
              (translateTypeNode tctx tn).highType
            | _ => mkHighTypeMd .TInt
          let paramNames := (decls params).map fun
            | .VariableDeclaration _ nameAnn .. => nameAnn.val
            | _ => ""
          let paramLocations := (decls params).map fun
            | .VariableDeclaration _ _ _ _ _ _ _ _ storageLoc _ _ => storageLoc.val
            | _ => ""
          functionSigs := functionSigs ++ [(fnNameAnn.val,
            { isPure := fnIsPure, isView := fnMutAnn.val == "view", memArrayParams, returnTypes,
              paramNames, paramLocations })]
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
                 fixedArrayLengths := fixedArrayLengths
                 nonPureFunctions := nonPureFunctions
                 functionSigs := functionSigs
                 enumDefs := enumDefs
                 udvtNames := udvtNames
                 constantDefs := constantDefs
                 fieldSolTypes := fieldSolTypes
                 stateVarInits := stateVarInits
                 immutableNames := immutableNames }
    let natspecInvariantStrs := stateVarInvariants.filterMap fun
      | .invariant e => some e | _ => none
    let natspecInvariantExprs ← natspecInvariantStrs.mapM fun e => do
      -- An invariant relates the state at every function boundary to itself;
      -- there is no "old" state to refer to.
      let toks := SpecParser.tokenize e
      if (toks.zip (toks.drop 1)).any (· == ("old", "(")) then
        throw (.unsupported s!"`old(...)` is not allowed in an invariant (`{e}`); use `ensures` for two-state properties")
      let parsed ← parseSpecExpr e
      -- Time and block values advance between transactions without any
      -- function running, so an invariant over them is not preserved by
      -- checking the contract's functions.
      if let some (_, what, _) := envConstants.find? fun (c, _, _) =>
          c != "this_address" && readsConstant c parsed then
        throw (.unsupported s!"`{what}` is not allowed in an invariant (`{e}`): it changes between transactions")
      -- The caller and the value sent belong to one transaction too. An
      -- invariant over them would be established for one caller and
      -- assumed for the next: with `owner == msg.sender` assumed on entry,
      -- `require(msg.sender != owner)` could never pass, and every
      -- property after it would be proven.
      if let some (_, what) := [("msg_sender", "msg.sender"), ("msg_value", "msg.value")].find?
          (readsVariable ·.1 parsed) then
        throw (.unsupported s!"`{what}` is not allowed in an invariant (`{e}`): it changes between transactions")
      pure parsed

    -- Pass 4: translate functions with struct field info, state context, and invariant nodes
    -- Invariant nodes are re-translated per function so that state variable references
    -- resolve correctly in each function's context.
    -- The base constructors deployment runs, most base first. Each gets
    -- the arguments that the most derived constructor naming its contract
    -- (`constructor() Base(7)`) gives it; those of an inheritance specifier
    -- (`is Base(7)`) are not in the AST, and are unknown.
    let tctx := { ctx with enumDefs, udvtNames }
    let ctorOf (c : String) : Option (Solidity.node SourceRange) :=
      (((ctx.contractNodes.lookup c).bind contractInfo?).map (·.members)).bind (·.find? isConstructorMember)
    let baseCtors : List BaseCtor := bases.filterMap fun b =>
      match ctorOf b.name with
      | some (.FunctionDefinition _ _ _ _ _ _ ps _ (.some_node _ bodyNode) _ mods) =>
        let params := match ps with
          | .ParameterList _ seq => seq.val.toList.filterMap fun
            | .VariableDeclaration _ n (.some_type_name _ tn) .. =>
              let t := translateTypeNode tctx tn
              some (n.val, t.highType, t.solName)
            | _ => none
          | _ => []
        let derived := linearization.takeWhile (· != b.name)
        let given := derived.findSome? fun x =>
          match ctorOf x with
          | some (.FunctionDefinition _ _ _ _ _ _ _ _ _ _ xMods) =>
            xMods.val.toList.findSome? fun
              | .ModifierInvocation _ m argsSeq =>
                if m.val == b.name then some (argsSeq.val.toList, x) else none
              | _ => none
          | _ => none
        some { contractName := b.name, params, body := bodyNode, modifiers := mods.val.toList,
               args := if params.isEmpty then some ([], nameAnn.val) else given,
               superImpls := superImplsFrom b.name }
      | _ => none
    -- Mappings some annotation of this contract, or of a base, sums.
    let summed := (contractDocAnn :: bases.map (·.doc) ++ taggedMembers.filterMap fun
        | (_, .FunctionDefinition _ _ _ _ _ _ _ _ _ doc _) => some doc
        | (_, .VariableDeclaration _ _ _ _ _ _ _ _ _ _ doc) => some doc
        | _ => none).flatMap (summedNames ·.val)
    -- A constructor that is not verified (it, or a base constructor it
    -- runs, uses a struct-valued mapping) establishes nothing, so the
    -- invariants are neither assumed nor checked: assuming them would make
    -- every obligation that relies on them pass.
    let usesStructMapping (n : Solidity.node SourceRange) : Bool :=
      structMappingNames.any (reprMentions (toString (repr n)) ·)
    let ctorSkipped := baseCtors.any (usesStructMapping ·.body) || ownMembers.any fun
      | .FunctionDefinition _ _ k _ _ _ _ _ bodyOpt _ _ =>
        k.val == "constructor" && match bodyOpt with
          | .some_node _ _ => structMappingNames.any (reprMentions (toString (repr bodyOpt)) ·)
          | _ => false
      | _ => false
    if ctorSkipped && !natspecInvariantExprs.isEmpty then
      warnings := warnings ++ [{ range := contractSr, message :=
        s!"the invariants of contract `{nameAnn.val}` are not verified: its constructor, which must establish them, is not verified" }]
    let invariants := if ctorSkipped then [] else natspecInvariantExprs
    let fnCtx := { baseFnCtx with contractInvariantNatspec := invariants,
                                   summedMappings := summed.eraseDups,
                                   contractInvariantTexts := if ctorSkipped then [] else natspecInvariantStrs,
                                   modifierDefs := modifierDefs,
                                   modifierSuperImpls := modifierSuperImpls,
                                   explicitImpls := explicitImpls,
                                   baseConstructors := baseCtors }
    for (owner, member) in taggedMembers do
      match member with
      | .FunctionDefinition fnSr fnNameAnn fnKindAnn _ _ _ _ _ bodyOpt fnDocAnn fnModifiers => do
          let fnDesc := functionDesc fnKindAnn.val fnNameAnn.val
          if isOwn owner then
            -- A modifier defined elsewhere (an imported base contract's) is
            -- not inlined. (A base constructor call, `Base(x)`, is fine.)
            for inv in fnModifiers.val do
              if let .ModifierInvocation invSr modName _ := inv then
                if !modifierDefs.any (·.1 == modName.val) && !linearization.contains modName.val then
                  warnings := warnings ++ [{ range := invSr, message :=
                    s!"modifier `{modName.val}` is not defined in this contract: {fnDesc} is verified without it" }]
          let bodyText := match bodyOpt with
            | .some_node _ _ => toString (repr bodyOpt)
            | _ => ""
          let hasBody := !(bodyOpt matches .missing_node _)
          let isCtor := fnKindAnn.val == "constructor"
          -- Keywords translateFunction honors for this function, and why the
          -- others have no effect.
          let allowed := if !hasBody then [] else
            ["requires", "ensures"] ++ (if isCtor then [] else ["modifies"]) ++
              (if reprHasLoop bodyText then ["loop-invariant"] else [])
          let reason : String → Option String := fun kw =>
            if !hasBody then some "it has no body, so it is not checked"
            else if kw == "modifies" && isCtor then some "frames are not checked for constructors"
            else if kw == "loop-invariant" then some "it has no loop"
            else none
          let fnAnnotations := parseStrataAnnotationsAt ctx.source fnDocAnn
          if isOwn owner then
            warnings := warnings ++ annotationWarnings ctx.source fnDesc allowed fnDocAnn reason
            -- Specs through struct-valued mappings are dropped by translateFunction.
            for (ann, r) in fnAnnotations do
              match ann with
              | .requires e | .ensures e =>
                if hasStructAccess e then
                  warnings := warnings ++ [{ range := r, message :=
                    s!"`@custom:strata {ann.keyword} {e}` on {fnDesc} is ignored: struct fields accessed through a mapping are not supported" }]
              | .modifies vars =>
                for (m, key) in SpecParser.unreadableModifiesKeys vars do
                  warnings := warnings ++ [{ range := r, message :=
                    s!"`@custom:strata modifies {m}[{key}]` on {fnDesc}: the key cannot be read, so the frame of `{m}` is not checked" }]
              | _ => pure ()
          -- Skip functions that reference struct-valued mappings (unsupported in
          -- Core); a constructor also when a base constructor it runs does.
          let usedStructMappings := structMappingNames.filter fun m =>
            reprMentions bodyText m ||
              (isCtor && baseCtors.any fun (b : BaseCtor) => reprMentions (toString (repr b.body)) m)
          if !usedStructMappings.isEmpty then
            if isOwn owner then
              let names := ", ".intercalate (usedStructMappings.map (s!"`{·}`"))
              let how := if usedStructMappings.any (reprMentions bodyText ·) then "it uses"
                else "a base constructor it runs uses"
              warnings := warnings ++ [{ range := fnSr, message :=
                s!"{fnDesc} is not verified: {how} the struct-valued mapping {names}, which is not supported" }]
          else do
            -- An inherited function is verified in this contract's context:
            -- its state, its invariants. `super` in it refers to the
            -- contracts after the one that defines it.
            let memberCtx := { fnCtx with superImpls := superImplsFrom owner }
            let memberCtx := if isOwn owner then memberCtx else { memberCtx with verifiedIn := some nameAnn.val }
            let proc ← translateFunction memberCtx member
            procedures := procedures ++ [proc]
      | _ => pure ()


    -- Without an explicit constructor, deployment runs only the default
    -- initialization and the state-variable initializers. Check that this
    -- initial state satisfies the invariants with an implicit, empty
    -- constructor; otherwise every function would assume invariants that
    -- nothing establishes (an unsatisfiable invariant would make every
    -- obligation pass). An abstract contract is checked the same way, as
    -- the initial state of the contracts that derive from it.
    let hasCtor := ownMembers.any fun
      | .FunctionDefinition _ _ k _ _ _ _ _ _ _ _ => k.val == "constructor"
      | _ => false
    if !invariants.isEmpty && !hasCtor && kindAnn.val == "contract" then
      let str (v : String) : StrataDDM.Ann String SourceRange := ⟨contractSr, v⟩
      let noParams : Solidity.node SourceRange := .ParameterList contractSr ⟨contractSr, #[]⟩
      let implicitCtor : Solidity.node SourceRange :=
        .FunctionDefinition contractSr (str "") (str "constructor") (str "nonpayable")
          (str "public") (str "false") noParams noParams
          (.some_node contractSr (.Block contractSr ⟨contractSr, #[]⟩)) (str "")
          ⟨contractSr, #[]⟩
      procedures := procedures ++ [← translateFunction fnCtx implicitCtor]

    let implOf (p : Procedure) : Option StmtExprMd := match p.body with
      | .Transparent e => some e
      | .Opaque _ impl _ => impl
      | _ => none

    -- The overridden implementations that `super.f(…)` and `X.f(…)` calls
    -- reach, directly or through one another.
    let mut emittedImpls : List String := []
    for _ in [0:overriddenImpls.length] do
      let called := procedures.flatMap fun p => ((implOf p).map calledNames).getD []
      let reached := overriddenImpls.filter fun (owner, f, _) =>
        let name := inheritedImplName owner f
        called.contains s!"{nameAnn.val}_{name}" && !emittedImpls.contains name
      if reached.isEmpty then break
      for (owner, f, m) in reached do
        let name := inheritedImplName owner f
        emittedImpls := emittedImpls ++ [name]
        if structMappingNames.any (reprMentions (toString (repr m)) ·) then
          throw (.unsupported s!"the implementation of `{f}` in `{owner}`, which a `super.{f}(...)` or `{owner}.{f}(...)` call reaches: it uses a struct-valued mapping, which is not supported")
        if let some impl := asInheritedImpl name m then
          procedures := procedures ++ [← translateFunction
            { fnCtx with superImpls := superImplsFrom owner, verifiedIn := some nameAnn.val } impl]

    -- A halt (assembly `return` or `stop`, `selfdestruct`) ends the whole
    -- transaction, keeping the state written so far. It is modelled as a
    -- return from the function it is in (see `haltLabel`): right in an
    -- entry point, whose postconditions and invariants are checked there,
    -- but a function that calls one containing a halt would continue after
    -- the call, and its remaining code be verified as if it ran. Such calls
    -- are rejected.
    let solidityName (proc : String) := (proc.drop (nameAnn.val.length + 1)).toString
    let halting := procedures.filterMap fun p =>
      if (implOf p).any containsHalt then some p.name.text else none
    for p in procedures do
      if let some callee := ((implOf p).map calledNames).getD [] |>.find? halting.contains then
        throw (.unsupported s!"the call of `{solidityName callee}` in `{solidityName p.name.text}`: `{solidityName callee}` may end the transaction (assembly `return` or `stop`, `selfdestruct`), and the code after the call would be verified as if it ran")

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

    return (procedures, types, warnings)
  | _ => throw (.internalError "Expected ContractDefinition")

/-! ## Annotations Nobody Reads -/

/-- Source ranges of the bodies of every function (including file-level
    functions) and modifier in `cmd`. -/
private def bodyRanges (cmd : Solidity.Command SourceRange) : List SourceRange :=
  let bodyOf : Solidity.node SourceRange → Option SourceRange
    | .FunctionDefinition _ _ _ _ _ _ _ _ (.some_node _ (.Block sr _)) _ _ => some sr
    | .ModifierDefinition _ _ _ (.some_node _ (.Block sr _)) => some sr
    | _ => none
  match cmd with
  | .SourceUnit _ nodesSeq =>
    nodesSeq.val.toList.flatMap fun
      | .ContractDefinition _ _ _ _ members _ _ => members.val.toList.filterMap bodyOf
      | n => (bodyOf n).toList

/-- The NatSpec comments whose annotations are accounted for: those of
    contracts, of their functions and state variables (read by the
    translator, or warned about one by one), and of file-level functions
    (warned about as unverified). -/
private def accountedDocs (cmd : Solidity.Command SourceRange)
    : List (StrataDDM.Ann String SourceRange) :=
  let docOf : Solidity.node SourceRange → Option (StrataDDM.Ann String SourceRange)
    | .FunctionDefinition _ _ _ _ _ _ _ _ _ doc _ => some doc
    | .VariableDeclaration _ _ _ stateVar _ _ _ _ _ _ doc =>
      if stateVar.val == "true" then some doc else none
    | _ => none
  match cmd with
  | .SourceUnit _ nodesSeq =>
    nodesSeq.val.toList.flatMap fun
      | .ContractDefinition _ _ _ _ members doc _ => doc :: members.val.toList.filterMap docOf
      | n => (docOf n).toList

/-- Warn about every annotation in the source that no accounted-for NatSpec
    comment contains: annotations inside function or modifier bodies (such
    as a `loop-invariant` above a loop), in `//` comments, in NatSpec that
    solc attaches to something the translator does not read (modifiers,
    events, errors, structs, enums) or to nothing (a detached block, text
    after the last member, a comment above `pragma`). solc attaches NatSpec
    only to the next declaration, so none of these reach the translator. -/
def unattachedAnnotations (cmd : Solidity.Command SourceRange) (source : String)
    : List TranslationWarning :=
  let docs := accountedDocs cmd |>.filter (!·.val.isEmpty)
  -- A comment solc gave no source range (an old solc) is matched by the
  -- text of its annotation lines instead.
  let unlocatedLines := docs.filter (·.ann == default) |>.flatMap (strataAnnotationLines ·.val)
  let bodies := bodyRanges cmd
  let midline := (midlineTagsInSource source).map fun r =>
    { range := r, message :=
        "`@custom:strata` in the middle of a comment line is ignored; " ++
        "an annotation must start its line" : TranslationWarning }
  midline ++ (annotationLinesInSource source).filterMap fun (r, lead) =>
    if docs.any (rangesOverlap r ·.ann) then none
    else if unlocatedLines.contains ((afterStrataTag? (textAt source r)).getD "") then none
    else
      let message :=
        if bodies.any (rangesOverlap r ·) then
          "`@custom:strata` annotation inside a function or modifier body is ignored; " ++
            "put it in the NatSpec comment above the function"
        else if lead == "//" || lead == "/*" then
          "`@custom:strata` annotation in a plain comment is ignored; " ++
            "NatSpec comments start with `///` or `/**`"
        else
          "`@custom:strata` annotation is not attached to a contract, function or state " ++
            "variable and is ignored"
      some { range := r, message }

/-! ## Top-Level Translation -/

/-- Translate a Solidity SourceUnit (top-level AST) to a Laurel Program.
    `solFilePath` is the path to the original .sol file, used for source location metadata.
    Pass `none` to skip metadata construction. -/
def solidityToLaurelWithWarnings (cmd : Solidity.Command SourceRange)
    (solFilePath : Option String := none) (source : Option String := none)
    (exprTypes : Std.HashMap (Nat × Nat × String) String := {})
    (assumeNoReentrancy : Bool := false)
    : Except TranslationError (Laurel.Program × List TranslationWarning) := do
  let ctx : TransCtx := { uri := solFilePath.map .file, source, exprTypes, assumeNoReentrancy }
  match cmd with
  | .SourceUnit _ nodesSeq => do
    -- The contracts and interfaces, whose names are types of addresses.
    let contractTypeNames := nodesSeq.val.toList.filterMap fun (node : Solidity.node SourceRange) =>
      match node with
      | .ContractDefinition _ nameAnn kindAnn .. =>
        if kindAnn.val == "library" then none else some nameAnn.val
      | _ => none
    let ctx := { ctx with contractTypeNames }
    -- Contracts are verified one by one, each as the flattening of its
    -- bases and itself, so every contract must be reachable by name.
    let contractNodes := nodesSeq.val.toList.filterMap
      fun (node : Solidity.node SourceRange) =>
        match node with
        | .ContractDefinition _ nameAnn .. => some (nameAnn.val, node)
        | _ => none
    let ctx := { ctx with contractNodes }
    let mut allProcedures : List Procedure := []
    let mut allTypes : List TypeDefinition := []
    let mut allWarnings : List TranslationWarning := []

    -- Pre-pass: collect top-level user-defined value types (`type Wei is uint256`)
    -- so contracts can resolve UDVT-typed locals/params/mappings to TInt.
    let mut topUdvtNames : List String := []
    for node in nodesSeq.val do
      match node with
      | .UserDefinedValueTypeDefinition _ udvtNameAnn _ =>
        topUdvtNames := topUdvtNames ++ [udvtNameAnn.val]
      | _ => pure ()
    let ctx := { ctx with udvtNames := ctx.udvtNames ++ topUdvtNames }

    for node in nodesSeq.val do
      match node with
      | .ContractDefinition _ _ _ _ _ _ _ => do
        let (procs, types, warnings) ← translateContract ctx node
        allProcedures := allProcedures ++ procs
        allTypes := allTypes ++ types
        allWarnings := allWarnings ++ warnings
      | .FunctionDefinition fnSr fnNameAnn _ _ _ _ _ _ _ _ _ =>
        allWarnings := allWarnings ++ [{ range := fnSr, message :=
          s!"file-level function `{fnNameAnn.val}` is not verified: functions outside a contract are not supported" }]
      | .PragmaDirective _ _ => pure ()  -- Skip pragmas
      | _ => pure ()  -- Skip unsupported top-level nodes

    -- Collect all mapping state variable names from procedure parameters.
    -- Mapping state vars appear as "<name>_in : Map[int, ...]" inputs of
    -- mutating functions, "<name>" inputs of view functions, and "<name>"
    -- outputs (a constructor has only the latter).
    let allMappingNames := allProcedures.foldl (fun acc proc =>
      acc ++ (proc.inputs.filterMap fun param =>
        match param.type.val with
        | .TMap _ _ =>
          let n := param.name.text
          some (if n.endsWith "_in" then (n.dropEnd 3).toString else n)
        | _ => none) ++
      (proc.outputs.filterMap fun param =>
        match param.type.val with
        | .TMap _ _ => some param.name.text
        | _ => none)) ([] : List String)
    let allMappingNames := allMappingNames.eraseDups

    -- Declare uninterpreted functions used by the translator.
    -- Each is a transparent procedure whose body is a deterministic hole,
    -- which Laurel lowers to an uninterpreted function of the inputs. This
    -- gives the solver functional consistency (same inputs → same output)
    -- but no other axioms. A bodiless procedure would instead be havocked
    -- independently at every call. The hole is taken modulo 2^256, so the
    -- result is a uint256 value like the Solidity result it stands for
    -- (otherwise the solver could pick negative "hashes").
    -- `$intMod` is the prelude's unchecked modulus: no `divisor is non-zero`
    -- obligation for the constant 2^256.
    let uint256Hole := mkStmtExprMd (mkCall "$intMod" [mkStmtExprMd .Hole, mkStmtExprMd (.LiteralInt (2 ^ 256))])
    let mkUninterpBinary (name : String) : Procedure := {
      name := name
      inputs := [{ name := "a", type := mkHighTypeMd .TInt },
                 { name := "b", type := mkHighTypeMd .TInt }]
      outputs := [{ name := "result", type := mkHighTypeMd .TInt }]
      preconditions := []
      decreases := none
      body := .Transparent uint256Hole
    }
    let mkUninterpUnary (name : String) : Procedure := {
      name := name
      inputs := [{ name := "a", type := mkHighTypeMd .TInt }]
      outputs := [{ name := "result", type := mkHighTypeMd .TInt }]
      preconditions := []
      decreases := none
      body := .Transparent uint256Hole
    }
    let mkUninterpN (name : String) (n : Nat) : Procedure := {
      name := name
      inputs := (List.range n).map fun i =>
        { name := s!"a{i}", type := mkHighTypeMd .TInt }
      outputs := [{ name := "result", type := mkHighTypeMd .TInt }]
      preconditions := []
      decreases := none
      body := .Transparent uint256Hole
    }
    let uninterpFunctions := [
      mkUninterpBinary "bit_and", mkUninterpBinary "bit_or",
      mkUninterpBinary "bit_xor", mkUninterpBinary "bit_shl",
      mkUninterpBinary "bit_shr", mkUninterpUnary "bit_not",
      mkUninterpUnary "keccak256", mkUninterpUnary "sha256",
      mkUninterpUnary "abi_encode", mkUninterpBinary "abi_encode2",
      mkUninterpN "abi_encode3" 3, mkUninterpN "abi_encode4" 4,
      mkUninterpN "abi_encode5" 5, mkUninterpN "abi_encode6" 6,
      mkUninterpUnary "abi_encodePacked", mkUninterpBinary "abi_encodePacked2",
      mkUninterpN "abi_encodePacked3" 3, mkUninterpN "abi_encodePacked4" 4,
      mkUninterpUnary "abi_encodeWithSelector",
      mkUninterpUnary "abi_encodeWithSignature",
      mkUninterpUnary "abi_decode",
      mkUninterpUnary "address_code", mkUninterpUnary "address_codehash"
    ]
    -- Values that may differ at every read (`gasleft()`, balances, whether
    -- a `send` succeeded): opaque procedures without an implementation,
    -- so each call returns a fresh value; they change no state.
    let envProcedure (name : String) (inputs : List Parameter) (type : HighTypeMd)
        (range : Option (String × String)) : Procedure := {
      name := name
      inputs := inputs
      outputs := [{ name := "result", type }]
      preconditions := []
      decreases := none
      body := .Opaque
        (match range with
          | some (what, solName) =>
            (mkRangeCond solName (mkStmtExprMd (mkIdentifier "result"))).toList.map fun c =>
              { condition := c, summary := some s!"type range of {what} ({solName})" }
          | none => [])
        none [{ targets := [] }]
    }
    let envProcedures := [
      envProcedure "gasleft" [] (mkHighTypeMd .TInt) (some ("gasleft()", "uint256")),
      envProcedure "this_balance" [] (mkHighTypeMd .TInt) (some ("address(this).balance", "uint256")),
      envProcedure "address_balance" [{ name := "a", type := mkHighTypeMd .TInt }]
        (mkHighTypeMd .TInt) (some ("address(a).balance", "uint256")),
      envProcedure "send_result" [] (mkHighTypeMd .TBool) none]
    -- Transaction constants (`block.timestamp`, …) that some function reads.
    let readsVar (name : String) (p : Procedure) : Bool :=
      p.preconditions.any (readsConstant name ·.condition) ||
      match p.body with
      | .Opaque posts impl _ => posts.any (readsConstant name ·.condition) || impl.any (readsConstant name)
      | .Transparent e => readsConstant name e
      | .Abstract posts => posts.any (readsConstant name ·.condition)
      | .External => false
    let constants : List Constant := envConstants.filterMap fun (c, _, _) =>
      if allProcedures.any (readsVar c) then some { name := mkIdent c, type := mkHighTypeMd .TInt }
      else none

    -- Declare sum() for each mapping state variable that appears in a sum() call in specs.
    -- sum : Map[int, int] → int, with update axiom:
    --   forall m : Map[int,int], k : int, v : int ::
    --     sum(update(m, k, v)) == sum(m) - select(m, k) + v
    -- Also: sum(mapConst(0)) == 0  (empty mapping has zero sum)
    let sumFunctions := allMappingNames.filterMap fun name =>
      if true then  -- declare sum for all mappings; unused ones don't affect z3
        let mapType := mkHighTypeMd (.TMap (mkHighTypeMd .TInt) (mkHighTypeMd .TInt))
        let mVar := mkStmtExprMd (mkIdentifier "m")
        let kVar := mkStmtExprMd (mkIdentifier "k")
        let vVar := mkStmtExprMd (mkIdentifier "v")
        -- sum(update(m, k, v)) == sum(m) - select(m, k) + v
        let updated := mkStmtExprMd (mkCall "update" [mVar, kVar, vVar])
        let sumUpdated := mkStmtExprMd (mkCall s!"sum_{name}" [updated])
        let sumM := mkStmtExprMd (mkCall s!"sum_{name}" [mVar])
        let selMK := mkStmtExprMd (mkCall "select" [mVar, kVar])
        let rhs := mkStmtExprMd (mkPrimOp .Add [
          mkStmtExprMd (mkPrimOp .Sub [sumM, selMK]), vVar])
        let updateAxiom := mkStmtExprMd (mkForall
          { name := "m", type := mapType }
          (mkStmtExprMd (mkForall
            { name := "k", type := mkHighTypeMd .TInt }
            (mkStmtExprMd (mkForall
              { name := "v", type := mkHighTypeMd .TInt }
              (mkStmtExprMd (mkPrimOp .Eq [sumUpdated, rhs])))))))
        -- sum(mapConst(0)) == 0
        let emptyMap := mkStmtExprMd (mkCall "mapConst" [mkStmtExprMd (.LiteralInt 0)])
        let sumEmpty := mkStmtExprMd (mkCall s!"sum_{name}" [emptyMap])
        let emptyAxiom := mkStmtExprMd (mkPrimOp .Eq [sumEmpty, mkStmtExprMd (.LiteralInt 0)])
        some {
          name := s!"sum_{name}"
          inputs := [{ name := "m", type := mapType }]
          outputs := [{ name := "result", type := mkHighTypeMd .TInt }]
          preconditions := []
          decreases := none
          body := .Abstract [
            { condition := updateAxiom, summary := none },
            { condition := emptyAxiom, summary := none }
          ]
        }
      else none

    return ({
      staticProcedures := uninterpFunctions ++ envProcedures ++ sumFunctions ++ allProcedures
      staticFields := []
      types := allTypes
      constants
    }, allWarnings)

/-- `solidityToLaurelWithWarnings` without the warnings. -/
def solidityToLaurel (cmd : Solidity.Command SourceRange) (solFilePath : Option String := none)
    : Except TranslationError Laurel.Program :=
  (·.1) <$> solidityToLaurelWithWarnings cmd solFilePath

end Strata.Solidity

