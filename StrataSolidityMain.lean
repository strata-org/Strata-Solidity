/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

-- Standalone CLI for Solidity verification via the Laurel pipeline.
import StrataSolidity
import Strata.Languages.Laurel.LaurelToCoreTranslator
import Strata.Languages.Core.Verifier
import Strata.Languages.Core.Options
import Strata.DL.Imperative.MetaData

open Core (VerifyOptions VerboseMode VCResult Outcome LExprModel)
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
        match fr.file with
        | .file path =>
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

/-- Classify a VCResult into 0=fail, 1=unknown, 2=pass. -/
private def statusOrder (o : Outcome) : Nat :=
  match o with
  | .fail | .implementationError _ => 0
  | .unknown => 1
  | .pass => 2

private def statusEmoji (o : Outcome) : String :=
  match o with
  | .fail | .implementationError _ => "❌"
  | .unknown => "❓"
  | .pass => "✅"

private def statusLabel (o : Outcome) : String :=
  match o with
  | .fail => "fail"
  | .implementationError _ => "implementation_error"
  | .unknown => "unknown"
  | .pass => "pass"

/-- Format verification results grouped by status with summary. -/
private def formatVcResultsWithLocation (vcResults : Array Core.VCResult)
    (sourceOpt : Option (String × String)) : String × Bool := Id.run do
  let mut nPass := 0
  let mut nFail := 0
  let mut nUnknown := 0
  for vcr in vcResults do
    match vcr.result with
    | .pass => nPass := nPass + 1
    | .fail | .implementationError _ => nFail := nFail + 1
    | .unknown => nUnknown := nUnknown + 1
  let sorted := vcResults.toList.toArray |>.qsort
    (fun a b => statusOrder a.result < statusOrder b.result)
  let mut s := ""
  let mut curSection := 3  -- sentinel
  for vcr in sorted do
    let sec := statusOrder vcr.result
    if sec != curSection then
      curSection := sec
      let (emoji, header, count) := match vcr.result with
        | .fail | .implementationError _ => ("❌", "Failures", nFail)
        | .unknown => ("❓", "Unknown", nUnknown)
        | .pass => ("✅", "Passed", nPass)
      if !s.isEmpty then s := s ++ "\n"
      s := s ++ s!"{emoji} {header} ({count}):\n"
    let locStr := match resolvePosition vcr sourceOpt with
      | some (line, col) => s!" at line {line}, col {col}"
      | none => ""
    s := s ++ s!"  {vcr.obligation.label}{locStr}\n"
    -- Counterexample for failures
    match vcr.result with
    | .fail | .implementationError _ =>
      let cex := formatPlainCounterexample vcr.lexprModel
      if !cex.isEmpty then s := s ++ cex ++ "\n"
    | _ => pure ()
  s := s ++ s!"\n{nPass} passed, {nFail} failed, {nUnknown} unknown out of {vcResults.size} total"
  (s, nFail > 0)

/-- Produce flat JSON array of results for scripting. -/
private def formatJsonResults (vcResults : Array Core.VCResult)
    (sourceOpt : Option (String × String)) : String :=
  let arr := vcResults.map fun vcr =>
    let baseFields : Array (String × Json) := #[
      ("name", Json.str vcr.obligation.label),
      ("status", Json.str (statusLabel vcr.result))
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
  let useArrays := args.contains "--array-theory"
  let dumpVcDir : Option String := match args.filter (·.startsWith "--dump-vc=") with
    | t :: _ => some (t.drop "--dump-vc=".length).toString
    | _ => none
  let timeoutVal : Nat := match args.filter (·.startsWith "--timeout=") with
    | t :: _ => (t.drop "--timeout=".length).toNat?.getD 10
    | _ => 10
  let flags := ["--verbose", "--sarif", "--json", "--array-theory"]
  let files := args.filter (fun a => !flags.contains a && !a.startsWith "--timeout=" && !a.startsWith "--dump-vc=")
  match files with
  | [filePath] =>
    let cmds ← readSolidityStrata' filePath
    let solSourceOpt ← tryReadSoliditySource filePath
    if cmds.size != 1 then
      exitFailure s!"Expected exactly one SourceUnit command, got {cmds.size}"
    let cmd := cmds[0]!

    if verbose then
      IO.println "==== Solidity AST (Ion) loaded ===="

    let sourcePathForMetadata := match solSourceOpt with
      | some (solPath, _) => solPath
      | none => filePath

    -- Translate Solidity AST → Laurel
    match Strata.Solidity.solidityToLaurel cmd (some sourcePathForMetadata) with
    | .error e =>
      exitFailure s!"Solidity to Laurel translation failed: {e}"
    | .ok laurelProgram =>
      if verbose then
        IO.println "\n==== Laurel Program ===="
        IO.println f!"{laurelProgram}"

      -- Translate Laurel → Core
      match Strata.Laurel.translate laurelProgram with
      | .error diagnostics =>
        exitFailure s!"Laurel to Core translation failed: {diagnostics}"
      | .ok (coreProgram, _modifiesDiags) =>
        if verbose then
          IO.println "\n==== Core Program ===="
          IO.print coreProgram

        -- Verify using Core verifier
        let vcResults ← match dumpVcDir with
          | some dir => do
            IO.FS.createDirAll ⟨dir⟩
            EIO.toIO
              (fun f => IO.Error.userError (toString f))
              (Core.verify coreProgram ⟨dir⟩ .none
                { VerifyOptions.default with
                  stopOnFirstError := false,
                  verbose := .quiet,
                  solver := "z3",
                  solverTimeout := timeoutVal,
                  useArrayTheory := useArrays })
          | none =>
            IO.FS.withTempDir (fun tempDir =>
              EIO.toIO
                (fun f => IO.Error.userError (toString f))
                (Core.verify coreProgram tempDir .none
                  { VerifyOptions.default with
                    stopOnFirstError := false,
                    verbose := .quiet,
                    solver := "z3",
                    solverTimeout := timeoutVal,
                    useArrayTheory := useArrays }))

        -- Print results
        if sarifMode then
          IO.println (StrataSolidity.Sarif.toSarif vcResults solSourceOpt)
        else if jsonMode then
          IO.println (formatJsonResults vcResults solSourceOpt)
        else
          IO.println "\n==== Verification Results ===="
          let (s, hasFailures) := formatVcResultsWithLocation vcResults solSourceOpt
          IO.println s
          if hasFailures then IO.Process.exit 1
  | _ =>
    IO.eprintln "Usage: strataSolidity <file.solidity.st.ion> [--verbose] [--sarif] [--json]"
    IO.Process.exit 1
