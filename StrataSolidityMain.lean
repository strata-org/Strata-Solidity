/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

-- Standalone CLI for Solidity verification via the Laurel pipeline.
import StrataSolidity
import StrataLaurel.Implementation.LaurelCompilationPipeline
import Strata.Languages.Core.Verifier
import Strata.Languages.Core.Options
import Strata.DL.Imperative.MetaData

open Core (VerifyOptions VerboseMode VCResult VCOutcome VCError LExprModel)
open Lean (Json toJson)

private def exitFailure {α} (message : String) : IO α := do
  IO.eprintln s!"Exception: {message}"
  IO.Process.exit 1

/-- Exit with an error. In the machine-readable modes, a document with the
    error is printed first, so that CI uploads (`if: always()`) and scripts
    see why nothing was verified. -/
private def failRun {α} (sarif json pipeline : Bool) (path message : String) : IO α := do
  if sarif then IO.println (StrataSolidity.Sarif.failureSarif path message)
  else if json then
    IO.println (Json.arr #[Json.mkObj [("name", "translation-error"),
      ("description", Json.str message), ("status", "implementation_error")]]).pretty
  else if pipeline then
    IO.println (toString (Json.mkObj [("error", Json.str message), ("obligations", Json.arr #[]),
      ("summary", Json.mkObj [("total", (0 : Nat)), ("passed", (0 : Nat)), ("failed", (0 : Nat)),
        ("unknown", (0 : Nat)), ("errors", (1 : Nat))])]))
  exitFailure message

/-- Read a Solidity Ion file, converting IO errors to a clean exit. -/
private def readSolidityStrata' (strataPath : String)
    : IO (Array (Strata.Solidity.Command Strata.SourceRange)) := do
  match ← Strata.Solidity.readSolidityStrata strataPath |>.toBaseIO with
  | .ok r => pure r
  | .error msg => exitFailure msg

/-- Derive the original .sol source path from a .solidity.st.ion path. -/
private def ionPathToSolidityPath (ionPath : String) : Option String :=
  if ionPath.endsWith ".solidity.st.ion" then
    let basePath := ionPath.dropEnd ".solidity.st.ion".length |>.toString
    some (basePath ++ ".sol")
  else
    none

/-- Try to read Solidity source file for source location reconstruction. -/
private def tryReadSoliditySource (ionPath : String) : IO (Option (String × String)) := do
  match ionPathToSolidityPath ionPath with
  | none => return none
  | some solPath =>
    try
      let content ← IO.FS.readFile solPath
      return some (solPath, content)
    catch _ =>
      return none

/-- Resolve source position for a VCResult. Returns (line, col) or none. -/
private def resolvePosition (vcr : VCResult) (sourceOpt : Option (String × String))
    : Option (Nat × Nat) :=
  match Imperative.getFileRange vcr.obligation.metadata with
  | some fr =>
    if fr.range.isNone then none
    else match sourceOpt with
      | some (srcPath, srcText) =>
        let path := match fr.file with | .file p => p
        if path == srcPath then
          let pos := (Lean.FileMap.ofString srcText).toPosition fr.range.start
          some (pos.line, pos.column)
        else none
      | none => none
  | none => none

/-- Print a translation warning to stderr as `<file>:<line>:<col>: warning: …`. -/
private def printWarning (sourcePath : String) (sourceOpt : Option (String × String))
    (w : Strata.Solidity.TranslationWarning) : IO Unit := do
  let loc := match sourceOpt with
    | some (_, text) =>
      let pos := (Lean.FileMap.ofString text).toPosition w.range.start
      s!"{sourcePath}:{pos.line}:{pos.column + 1}"
    | none => sourcePath
  IO.eprintln s!"{loc}: warning: {w.message}"

/-- Format a counterexample for plain-text output (`inputs`: see
    `Obligations.displayVarName`). -/
private def formatPlainCounterexample (vcr : VCResult) (inputs : Std.HashSet String)
    (source? : Option String) : String :=
  let entries := StrataSolidity.Obligations.counterexample vcr inputs source?
  if entries.isEmpty then ""
  else "\n".intercalate (entries.map fun (name, val) => s!"        {name} = {val}")

/-- A passing obligation located in Laurel's prelude
    (`CoreDefinitionsForLaurel.lean`), which contributes well-formedness
    checks for its own operator wrappers to every program. They are not
    about the user's contract, so successful ones are not reported; failing
    or inconclusive ones are kept so an upstream regression stays visible.
    The prelude is matched by its file name, so a renamed prelude makes
    these obligations reappear rather than hiding user ones. -/
private def isPassingPreludeVc (vcr : VCResult) : Bool :=
  vcr.isSuccess &&
  match Imperative.getFileRange vcr.obligation.metadata with
  | some { file := .file path, .. } => path.endsWith "/CoreDefinitionsForLaurel.lean"
  | none => false

open StrataSolidity.Sarif (Verdict verdict)

/-- Section order in text output: errors, failures, unknown, passed. -/
private def statusOrder (vcr : VCResult) : Nat :=
  match verdict vcr with
  | .error _ => 0
  | .fail => 1
  | .unknown => 2
  | .pass => 3

private def statusLabel (vcr : VCResult) : String :=
  match verdict vcr with
  | .pass => "pass"
  | .fail => "fail"
  | .unknown => "unknown"
  | .error _ => "implementation_error"

/-- Format verification results grouped by status with summary. The flag
    is whether the run must fail: a refuted obligation or a verification
    error (REQ-CLI-050). -/
private def formatVcResultsWithLocation (vcResults : Array Core.VCResult)
    (sourceOpt : Option (String × String)) (inputs : Std.HashSet String) : String × Bool := Id.run do
  let count (p : Verdict → Bool) := (vcResults.filter (p <| verdict ·)).size
  let nPass := count (· matches .pass)
  let nFail := count (· matches .fail)
  let nUnknown := count (· matches .unknown)
  let nError := count (· matches .error _)
  let sorted := vcResults.toList.toArray |>.qsort
    (fun a b => statusOrder a < statusOrder b)
  let mut s := ""
  let mut curSection := 4  -- sentinel
  for vcr in sorted do
    let sec := statusOrder vcr
    if sec != curSection then
      curSection := sec
      let (emoji, header, n) := match verdict vcr with
        | .error _ => ("⚠️", "Errors", nError)
        | .fail => ("❌", "Failures", nFail)
        | .unknown => ("❓", "Unknown", nUnknown)
        | .pass => ("✅", "Passed", nPass)
      if !s.isEmpty then s := s ++ "\n"
      s := s ++ s!"{emoji} {header} ({n}):\n"
    let locStr := match resolvePosition vcr sourceOpt with
      | some (line, col) => s!" at line {line}, col {col + 1}"
      | none => ""
    s := s ++ s!"  {StrataSolidity.Obligations.name vcr sourceOpt}{locStr}\n"
    match verdict vcr with
    | .fail =>
      -- Counterexample for failures
      let cex := formatPlainCounterexample vcr inputs (sourceOpt.map (·.2))
      if !cex.isEmpty then s := s ++ cex ++ "\n"
    | .error e => s := s ++ s!"        {e}\n"
    | _ => pure ()
  let errors := if nError > 0 then s!", {nError} errors" else ""
  s := s ++ s!"\n{nPass} passed, {nFail} failed, {nUnknown} unknown{errors} out of {vcResults.size} total"
  (s, nFail > 0 || nError > 0)

/-- Line and (1-based) column of a translation warning. -/
private def warningPosition (sourceOpt : Option (String × String))
    (w : Strata.Solidity.TranslationWarning) : Option (Nat × Nat) :=
  sourceOpt.map fun (_, text) =>
    let pos := (Lean.FileMap.ofString text).toPosition w.range.start
    (pos.line, pos.column + 1)

/-- Produce flat JSON array of results for scripting: one entry per
    obligation, then one per annotation or function that is not verified
    (`"status": "not_verified"`, the warnings). -/
private def formatJsonResults (vcResults : Array Core.VCResult)
    (sourceOpt : Option (String × String))
    (warnings : List Strata.Solidity.TranslationWarning) : String :=
  let arr := vcResults.map fun vcr =>
    let baseFields : Array (String × Json) := #[
      ("name", Json.str vcr.obligation.label),
      ("description", Json.str (StrataSolidity.Obligations.name vcr sourceOpt)),
      ("status", Json.str (statusLabel vcr))
    ]
    let fields := match resolvePosition vcr sourceOpt with
    | some (line, col) =>
      baseFields.push ("line", toJson line) |>.push ("col", toJson (col + 1))
    | none => baseFields
    Json.mkObj fields.toList
  let notVerified := warnings.toArray.map fun w =>
    let base : List (String × Json) :=
      [("name", "not-verified"), ("description", Json.str w.message), ("status", "not_verified")]
    match warningPosition sourceOpt w with
    | some (line, col) => Json.mkObj (base ++ [("line", toJson line), ("col", toJson col)])
    | none => Json.mkObj base
  (Json.arr (arr ++ notVerified)).pretty

/-- Main entry point: `strataSolidity <file> [--verbose] [--sarif] [--json]` -/
def main (args : List String) : IO Unit := do
  let verbose := args.contains "--verbose"
  let sarifMode := args.contains "--sarif"
  let jsonMode := args.contains "--json"
  let pipelineJson := args.contains "--pipeline-json"
  let strict := args.contains "--strict"
  -- Array theory is the default, as in Laurel's own verification entry
  -- points: maps become SMT arrays instead of quantified select/update
  -- axioms, which z3 (with MBQI off) often cannot refute. Without it,
  -- refutable obligations tend to come back `unknown` with no
  -- counterexample. `--array-theory` is still accepted for compatibility.
  let useArrays := !args.contains "--no-array-theory"
  let dumpVcDir : Option String := match args.filter (·.startsWith "--dump-vc=") with
    | t :: _ => some (t.drop "--dump-vc=".length).toString
    | _ => none
  let solSourcePath : Option String := match args.filter (·.startsWith "--sol-source=") with
    | t :: _ => some (t.drop "--sol-source=".length).toString
    | _ => none
  let timeoutVal : Nat := match args.filter (·.startsWith "--timeout=") with
    | t :: _ => (t.drop "--timeout=".length).toNat?.getD 10
    | _ => 10
  let flags := ["--verbose", "--sarif", "--json", "--array-theory", "--no-array-theory", "--pipeline-json", "--from-sol", "--strict"]
  let files := args.filter (fun a => !flags.contains a && !a.startsWith "--timeout=" && !a.startsWith "--dump-vc=" && !a.startsWith "--sol-source=")
  match files with
  | [filePath] =>
    -- Frontend selection: `.sol` inputs (or --from-sol) go through the
    -- in-Lean frontend (solc --standard-json → typed AST, no Ion round
    -- trip); `.solidity.st.ion` inputs use the Ion reader.
    let useSolFrontend := args.contains "--from-sol" || filePath.endsWith ".sol"
    let cmd ←
      if useSolFrontend then do
        match ← Strata.Solidity.SolcAst.parseFile ⟨filePath⟩ with
        | .ok cmd => pure cmd
        | .error e => failRun sarifMode jsonMode pipelineJson filePath s!"Failed to parse {filePath}: {e}"
      else do
        let cmds ← readSolidityStrata' filePath
        if cmds.size != 1 then
          exitFailure s!"Expected exactly one SourceUnit command, got {cmds.size}"
        pure cmds[0]!
    let solSourceOpt ← match solSourcePath with
      | some p => do
        try
          let content ← IO.FS.readFile p
          pure (some (p, content))
      catch _ => tryReadSoliditySource filePath
      | none =>
        if useSolFrontend then do
          -- The input IS the source file.
          try pure (some (filePath, ← IO.FS.readFile filePath))
          catch _ => pure none
        else tryReadSoliditySource filePath

    if verbose then
      IO.println s!"==== Solidity AST ({if useSolFrontend then "solc, in-Lean frontend" else "Ion"}) loaded ===="

    let sourcePathForMetadata := match solSourcePath with
      | some p => p
      | none => match solSourceOpt with
        | some (solPath, _) => solPath
        | none => filePath

    -- Translate Solidity AST → Laurel
    match Strata.Solidity.solidityToLaurelWithWarnings cmd (some sourcePathForMetadata)
        (solSourceOpt.map (·.2)) with
    | .error e =>
      failRun sarifMode jsonMode pipelineJson filePath s!"Solidity to Laurel translation failed: {e}"
    | .ok (laurelProgram, translationWarnings) =>
      -- Report everything the translator did not verify, so nothing is
      -- dropped silently. Under `--strict` they make the run fail.
      let bodyWarnings := match solSourceOpt with
        | some (_, text) => Strata.Solidity.unattachedAnnotations cmd text
        | none => []
      let warnings := (translationWarnings ++ bodyWarnings).toArray.qsort
        (fun a b => a.range.start.byteIdx < b.range.start.byteIdx) |>.toList
      for w in warnings do printWarning sourcePathForMetadata solSourceOpt w
      let laurelStr := toString (f!"{laurelProgram}")
      if verbose then
        IO.println "\n==== Laurel Program ===="
        IO.println laurelStr

      -- Translate Laurel → Core
      let (coreOpt, translateDiags) ← Strata.Laurel.translate {} laurelProgram
      match coreOpt with
      | none =>
        failRun sarifMode jsonMode pipelineJson filePath s!"Laurel to Core translation failed: {translateDiags}"
      | some coreProgram =>
        let coreStr := toString (f!"{coreProgram}")
        if verbose then
          IO.println "\n==== Core Program ===="
          IO.print coreStr

        -- Verify using Core verifier
        let verifyOpts : VerifyOptions :=
          { VerifyOptions.default with
            stopOnFirstError := false,
            verbose := .quiet,
            solver := "z3",
            solverTimeout := timeoutVal,
            useArrayTheory := useArrays,
            -- z3 abbreviates nested array values (the heap, nested
            -- mappings) with `let` when they are deep or repeat a large
            -- subterm, and Core's model reader cannot parse `let`: the
            -- whole counterexample would be dropped.
            solverOptions := #[("pp.max_depth", "1000"), ("pp.min_alias_size", "1000000")] }
        -- Verify each user procedure in its own Core.verify call. Core shares
        -- one SMT prefix across the obligations of a call, so axioms needed
        -- by one procedure (e.g. the quantified `mapConst` axiom of a
        -- constructor that zero-initializes a mapping, or heap axioms
        -- without array theory) would otherwise reach every VC of the
        -- contract, and z3 (MBQI off) answers `unknown` instead of
        -- refuting an unrelated false property. The SMT files of each
        -- procedure go to their own subdirectory.
        --
        -- A user procedure `C_f` is the Core procedure `C_f`, or
        -- `$ov<n>$C_f` for each overload of `f`; each goes with the
        -- procedures that check that its contract is well defined
        -- (`<proc>$pre<i>`, `<proc>$post<i>`: a division in a `requires`
        -- or `ensures`). If a user procedure has no Core counterpart,
        -- verify the whole program at once rather than risk skipping
        -- obligations.
        let userProcs := (laurelProgram.staticProcedures.filterMap fun p =>
          match p.body with
          | .Opaque _ (some _) _ => some p.name.text
          | _ => none).eraseDups
        let coreNames := coreProgram.decls.filterMap fun d =>
          match d with
          | .proc pr _ => some (toString pr.header.name)
          | _ => none
        let isOverloadOf (name core : String) : Bool :=
          match core.splitOn "$" with
          | ["", ov, base] => ov.startsWith "ov" && (ov.drop 2).toString.all Char.isDigit && base == name
          | _ => false
        let companions (core : String) : List String :=
          coreNames.filter fun c =>
            let rest := (c.drop core.length).toString
            c.startsWith core && (rest.startsWith "$pre" || rest.startsWith "$post") &&
              ((rest.drop (if rest.startsWith "$pre" then 4 else 5)).toString.all Char.isDigit)
        let groups := userProcs.map fun name =>
          (name, coreNames.filter fun c => c == name || isOverloadOf name c)
        let perProcedure := groups.all (!·.2.isEmpty)
        -- Each result is paired with the directory holding its SMT files and
        -- the procedure it belongs to (empty if verified all at once).
        let verifyIn (dir : System.FilePath) : IO (Array (VCResult × System.FilePath × String)) := do
          let run (d : System.FilePath) (procName : String) (opts : VerifyOptions) := do
            let rs ← EIO.toIO (fun f => IO.Error.userError (toString f))
              (Core.verify coreProgram d opts)
            pure (rs.map (·, d, procName))
          if perProcedure then
            let mut acc := #[]
            for core in groups.flatMap (·.2) do
              let sub := dir / core
              IO.FS.createDirAll sub
              acc := acc ++ (← run sub core { verifyOpts with proceduresToVerify := some (core :: companions core) })
            pure acc
          else run dir "" verifyOpts
        let (located, _smtDir) ← match dumpVcDir with
          | some dir => do
            IO.FS.createDirAll ⟨dir⟩
            let r ← verifyIn ⟨dir⟩
            pure (r, (⟨dir⟩ : System.FilePath))
          | none =>
            let smtDirEnv ← IO.getEnv "STRATA_SMT_DIR"
            -- For --pipeline-json, always keep SMT files so we can read them
            let useFixedDir := smtDirEnv.isSome || pipelineJson
            if useFixedDir then
              let dir : System.FilePath := match smtDirEnv with
                | some d => d
                | none => "/tmp/strata-pipeline-smt"
              IO.FS.createDirAll dir
              -- Clean previous run's files (and per-procedure subdirectories)
              let entries ← (dir.readDir).catchExceptions (fun _ => pure #[])
              for e in entries do
                if e.fileName.endsWith ".smt2" then
                  IO.FS.removeFile e.path |>.catchExceptions (fun _ => pure ())
                else if ← e.path.isDir then
                  IO.FS.removeDirAll e.path |>.catchExceptions (fun _ => pure ())
              let result ← verifyIn dir
              pure (result, dir)
            else
              let r ← IO.FS.withTempDir verifyIn
              pure (r, ("" : System.FilePath))

        let located := located.filter (!isPassingPreludeVc ·.1)
        let vcResults := located.map (·.1)

        -- Print results
        if pipelineJson then
          let obligations ← located.toList.mapM fun ((r : VCResult), smtDir, _) => do
            let status := match verdict r with
              | .pass => "pass"
              | .fail => "fail"
              | .unknown => "unknown"
              | .error _ => "error"
            -- Try to read the SMT file for this obligation
            let smtContent ← do
              let candidates ← (smtDir.readDir).catchExceptions (fun _ => pure #[])
              -- Core names each file `<sanitized label>_<counter>.smt2`;
              -- match that shape exactly (a substring test also matched
              -- other obligations' files, and nothing once labels gained
              -- parentheses). Of several paths, take the first.
              let pre := Core.SMT.sanitizeFilenameCapped r.obligation.label ++ "_"
              let counterOf (name : String) : Option Nat :=
                if name.startsWith pre && name.endsWith ".smt2" then
                  ((name.drop pre.length).dropEnd ".smt2".length).toString.toNat?
                else none
              let matching := candidates.filterMap fun e => (counterOf e.fileName).map (·, e)
              match (matching.qsort (·.1 < ·.1)).toList.head? with
              | some (_, entry) => (IO.FS.readFile entry.path).catchExceptions (fun _ => pure "")
              | none => pure ""
            let smtResult := match verdict r with
              | .pass => "unsat"
              | .fail => "sat"
              | .unknown => "unknown"
              | .error _ => "error"
            return Json.mkObj [
              ("label", r.obligation.label),
              ("status", status),
              ("smt", Json.str smtContent),
              ("smtResult", Json.str smtResult)
            ]
          let pipeline := Json.mkObj [
            ("laurel", Json.str (toString laurelStr)),
            ("core", Json.str (toString coreStr)),
            ("obligations", Json.arr obligations.toArray),
            ("summary", Json.mkObj [
              ("total", vcResults.size),
              ("passed", (vcResults.filter (verdict · matches .pass)).size),
              ("failed", (vcResults.filter (verdict · matches .fail)).size),
              -- Neither proven nor refuted, timeouts included; `errors` are
              -- obligations nothing checked (total = passed + failed +
              -- unknown + errors).
              ("unknown", (vcResults.filter (verdict · matches .unknown)).size),
              ("errors", (vcResults.filter (verdict · matches .error _)).size),
              ("notVerified", warnings.length)
            ]),
            -- Annotations and functions that are not verified (the warnings).
            ("warnings", Json.arr (warnings.toArray.map fun w =>
              Json.mkObj ([("message", Json.str w.message)] ++
                match warningPosition solSourceOpt w with
                | some (line, col) => [("line", toJson line), ("col", toJson col)]
                | none => [])))
          ]
          IO.println (toString pipeline)
        else if sarifMode then
          IO.println (StrataSolidity.Sarif.toSarif (located.map fun (r, _, p) => (r, p)) solSourceOpt
            (warnings.map fun w => (w.range.start, w.message)))
        else if jsonMode then
          IO.println (formatJsonResults vcResults solSourceOpt warnings)
        else
          IO.println "\n==== Verification Results ===="
          let inputs := Std.HashSet.ofList (laurelProgram.staticProcedures.flatMap
            (·.inputs.map (·.name.text)))
          let (s, hasFailures) := formatVcResultsWithLocation vcResults solSourceOpt inputs
          IO.println s
          if !warnings.isEmpty then
            IO.println s!"⚠️  {warnings.length} annotation(s) or function(s) not verified (see warnings)"
          if hasFailures then IO.Process.exit 1
        -- `--strict`: succeed only if every obligation is proven and nothing
        -- was left unverified, in every output mode (without it, machine
        -- modes leave the verdict to the consumer and text mode fails only
        -- on refuted obligations).
        if strict then
          let unproven := (vcResults.filter (!·.isSuccess)).size
          if unproven > 0 || !warnings.isEmpty then
            IO.eprintln s!"error: --strict: {unproven} obligation(s) not proven, {warnings.length} annotation(s) or function(s) not verified"
            IO.Process.exit 1
  | _ =>
    IO.eprintln "Usage: strataSolidity <file.sol | file.solidity.st.ion> [--verbose] [--sarif] [--json] [--strict]"
    IO.Process.exit 1
