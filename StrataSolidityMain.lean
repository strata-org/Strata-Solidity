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

open Core (VerifyOptions VerboseMode)

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

/-- Format verification results with source locations. -/
private def formatVcResultsWithLocation (vcResults : Array Core.VCResult)
    (sourceOpt : Option (String × String)) : String := Id.run do
  let mut s := ""
  for vcResult in vcResults do
    let (locationPrefix, locationSuffix) :=
      match Imperative.getFileRange vcResult.obligation.metadata with
      | some fr =>
        if fr.range.isNone then ("", "")
        else
          match sourceOpt with
          | some (srcPath, srcText) =>
            match fr.file with
            | .file path =>
              if path == srcPath then
                let pos := (Lean.FileMap.ofString srcText).toPosition fr.range.start
                match vcResult.result with
                | .fail => (s!"Assertion failed at line {pos.line}, col {pos.column}: ", "")
                | _ => ("", s!" (at line {pos.line}, col {pos.column})")
              else
                match vcResult.result with
                | .fail => (s!"Assertion failed at byte {fr.range.start}: ", "")
                | _ => ("", s!" (at byte {fr.range.start})")
          | none =>
            match vcResult.result with
            | .fail => (s!"Assertion failed at byte {fr.range.start}: ", "")
            | _ => ("", s!" (at byte {fr.range.start})")
      | none => ("", "")
    s := s ++ s!"{locationPrefix}{vcResult.obligation.label}: {Std.format vcResult.result}{locationSuffix}\n"
  return s

/-- Main entry point: `strataSolidity <file> [--verbose] [--sarif]` -/
def main (args : List String) : IO Unit := do
  let verbose := args.contains "--verbose"
  let sarifMode := args.contains "--sarif"
  let files := args.filter (· != "--verbose" && · != "--sarif")
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
        let vcResults ← IO.FS.withTempDir (fun tempDir =>
            EIO.toIO
              (fun f => IO.Error.userError (toString f))
              (Core.verify coreProgram tempDir .none
                { VerifyOptions.default with
                  stopOnFirstError := false,
                  verbose := .quiet,
                  solver := "z3" }))

        -- Print results with source locations
        if sarifMode then
          IO.println (StrataSolidity.Sarif.toSarif vcResults solSourceOpt)
        else
          IO.println "\n==== Verification Results ===="
          let s := formatVcResultsWithLocation vcResults solSourceOpt
          IO.println s
  | _ =>
    IO.eprintln "Usage: strataSolidity <file.solidity.st.ion> [--verbose] [--sarif]"
    IO.Process.exit 1
