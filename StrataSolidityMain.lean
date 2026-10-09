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

/-- Format counterexample for plain-text output. -/
private def formatPlainCounterexample (cex : LExprModel) : String :=
  if cex.isEmpty then ""
  else
    let entries := cex.map fun (id, e) =>
      let name := StrataSolidity.Sarif.cleanVarName (toString id)
      let val := toString e
      s!"        {name} = {val}"
    "\n" ++ "\n".intercalate entries

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

/-- Classify a VCResult into 0=fail, 1=unknown, 2=pass. -/
private def statusOrder (vcr : VCResult) : Nat :=
  if vcr.isFailure then 0
  else if vcr.isSuccess then 2
  else 1

private def statusEmoji (vcr : VCResult) : String :=
  if vcr.isFailure then "❌"
  else if vcr.isSuccess then "✅"
  else "❓"

private def statusLabel (vcr : VCResult) : String :=
  match vcr.outcome with
  | .error _ => "implementation_error"
  | .ok _ =>
    if vcr.isFailure then "fail"
    else if vcr.isSuccess then "pass"
    else "unknown"

/-- Format verification results grouped by status with summary. -/
private def formatVcResultsWithLocation (vcResults : Array Core.VCResult)
    (sourceOpt : Option (String × String)) : String × Bool := Id.run do
  let mut nPass := 0
  let mut nFail := 0
  let mut nUnknown := 0
  for vcr in vcResults do
    if vcr.isSuccess then nPass := nPass + 1
    else if vcr.isFailure then nFail := nFail + 1
    else nUnknown := nUnknown + 1
  let sorted := vcResults.toList.toArray |>.qsort
    (fun a b => statusOrder a < statusOrder b)
  let mut s := ""
  let mut curSection := 3  -- sentinel
  for vcr in sorted do
    let sec := statusOrder vcr
    if sec != curSection then
      curSection := sec
      let (emoji, header, count) :=
        if vcr.isFailure then ("❌", "Failures", nFail)
        else if vcr.isSuccess then ("✅", "Passed", nPass)
        else ("❓", "Unknown", nUnknown)
      if !s.isEmpty then s := s ++ "\n"
      s := s ++ s!"{emoji} {header} ({count}):\n"
    let locStr := match resolvePosition vcr sourceOpt with
      | some (line, col) => s!" at line {line}, col {col}"
      | none => ""
    s := s ++ s!"  {vcr.obligation.label}{locStr}\n"
    -- Counterexample for failures
    if vcr.isFailure then
      let cex := formatPlainCounterexample vcr.lexprModel
      if !cex.isEmpty then s := s ++ cex ++ "\n"
  s := s ++ s!"\n{nPass} passed, {nFail} failed, {nUnknown} unknown out of {vcResults.size} total"
  (s, nFail > 0)

/-- Produce flat JSON array of results for scripting. -/
private def formatJsonResults (vcResults : Array Core.VCResult)
    (sourceOpt : Option (String × String)) : String :=
  let arr := vcResults.map fun vcr =>
    let baseFields : Array (String × Json) := #[
      ("name", Json.str vcr.obligation.label),
      ("status", Json.str (statusLabel vcr))
    ]
    let fields := match resolvePosition vcr sourceOpt with
    | some (line, col) =>
      baseFields.push ("line", toJson line) |>.push ("col", toJson col)
    | none => baseFields
    Json.mkObj fields.toList
  (Json.arr arr).pretty

/-- Main entry point: `strataSolidity <file> [--verbose] [--sarif] [--json]` -/
def main (args : List String) : IO Unit := do
  let verbose := args.contains "--verbose"
  let sarifMode := args.contains "--sarif"
  let jsonMode := args.contains "--json"
  let pipelineJson := args.contains "--pipeline-json"
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
  let flags := ["--verbose", "--sarif", "--json", "--array-theory", "--no-array-theory", "--pipeline-json", "--from-sol"]
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
        | .error e => exitFailure s!"Failed to parse {filePath}: {e}"
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
    match Strata.Solidity.solidityToLaurel cmd (some sourcePathForMetadata) with
    | .error e =>
      exitFailure s!"Solidity to Laurel translation failed: {e}"
    | .ok laurelProgram =>
      let laurelStr := toString (f!"{laurelProgram}")
      if verbose then
        IO.println "\n==== Laurel Program ===="
        IO.println laurelStr

      -- Translate Laurel → Core
      let (coreOpt, translateDiags) ← Strata.Laurel.translate {} laurelProgram
      match coreOpt with
      | none =>
        exitFailure s!"Laurel to Core translation failed: {translateDiags}"
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
        let (vcResults, smtDir) ← match dumpVcDir with
          | some dir => do
            IO.FS.createDirAll ⟨dir⟩
            let r ← EIO.toIO
              (fun f => IO.Error.userError (toString f))
              (Core.verify coreProgram ⟨dir⟩
                verifyOpts)
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
              -- Clean previous run's files
              let entries ← (dir.readDir).catchExceptions (fun _ => pure #[])
              for e in entries do
                if e.fileName.endsWith ".smt2" then
                  IO.FS.removeFile e.path |>.catchExceptions (fun _ => pure ())
              let result ← EIO.toIO
                (fun f => IO.Error.userError (toString f))
                (Core.verify coreProgram dir
                  verifyOpts)
              pure (result, dir)
            else
              let r ← IO.FS.withTempDir (fun tempDir =>
                EIO.toIO
                  (fun f => IO.Error.userError (toString f))
                  (Core.verify coreProgram tempDir
                    verifyOpts))
              pure (r, ("" : System.FilePath))

        let vcResults := vcResults.filter (!isPassingPreludeVc ·)

        -- Print results
        if pipelineJson then
          let obligations ← vcResults.toList.mapM fun (r : VCResult) => do
            let status := if r.isSuccess then "pass"
              else if r.isFailure then "fail"
              else "unknown"
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
            let smtResult := if r.isSuccess then "unsat" else if r.isFailure then "sat" else "unknown"
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
              ("passed", (vcResults.filter VCResult.isSuccess).size),
              ("failed", (vcResults.filter VCResult.isFailure).size),
              ("unknown", (vcResults.filter VCResult.isUnknown).size)
            ])
          ]
          IO.println (toString pipeline)
        else if sarifMode then
          IO.println (StrataSolidity.Sarif.toSarif vcResults solSourceOpt)
        else if jsonMode then
          IO.println (formatJsonResults vcResults solSourceOpt)
        else
          IO.println "\n==== Verification Results ===="
          let (s, hasFailures) := formatVcResultsWithLocation vcResults solSourceOpt
          IO.println s
          if hasFailures then IO.Process.exit 1
  | _ =>
    IO.eprintln "Usage: strataSolidity <file.sol | file.solidity.st.ion> [--verbose] [--sarif] [--json]"
    IO.Process.exit 1
