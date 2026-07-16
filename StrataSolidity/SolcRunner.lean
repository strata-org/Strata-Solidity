/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/
module

public import Lean.Data.Json
import Lean.Data.Json.Parser

/-!
# Solc runner — invoke `solc --standard-json` and capture its AST output

Group B (front-end-in-Lean) of `.kiro/specs/pipeline-language-rationalization/`.
This file replaces the subprocess call inside `Tools/Solidity/src/solast.py`
with a typed Lean entry point. The next file (`SolcAstParser.lean`) walks
the JSON output and produces a `Solidity.node SourceRange` value, removing
the Ion intermediate from the default verification path.

## Status

Subprocess runner only. JSON output is captured as `Lean.Json` and returned;
the AST extraction (`getAst`) does the minimal navigation `solc-output → sources[*].ast`.
Translation from the JSON AST to the Lean Solidity ADT is in `SolcAstParser.lean`
(scaffold for now).

## Why subprocess instead of linking solc directly

solc is GPL-3.0; linking it would force the host program under GPL. Invoking
it as a subprocess via `IO.Process.output` is the standard isolation pattern
and matches what `solast.py` already does.

## Project-root discovery

Mirrors the Python's behavior: walk up from the input file looking for
`foundry.toml`, `hardhat.config.{js,ts}`, `package.json`, or `remappings.txt`,
to set `--allow-paths` correctly for solc. Falls back to the input's parent
directory if no marker is found within 10 levels.
-/

public section

namespace Strata.Solidity.Solc

open Lean (Json)

/-- Errors that can come out of running `solc`. -/
inductive Error where
  /-- solc exited non-zero. -/
  | exitCode (code : UInt32) (stderr : String)
  /-- solc produced output that wasn't valid JSON. -/
  | invalidJson (msg : String)
  /-- solc returned a JSON object containing fatal errors in its `errors` array. -/
  | fatalDiagnostics (formatted : Array String)
  /-- The output JSON didn't contain a `sources[*].ast` we could find. -/
  | noAst
  deriving Repr

instance : ToString Error where
  toString
    | .exitCode c stderr =>
      s!"solc exited with code {c}:\n{stderr}"
    | .invalidJson msg =>
      s!"solc produced invalid JSON: {msg}"
    | .fatalDiagnostics formatted =>
      "solc reported fatal diagnostics:\n" ++ String.intercalate "\n" formatted.toList
    | .noAst =>
      "solc output contained no AST"

/-- Project markers we walk up looking for, mirroring `solast.py`. -/
private def projectMarkers : List String :=
  ["foundry.toml", "hardhat.config.js", "hardhat.config.ts",
   "package.json", "remappings.txt"]

/-- Walk up from `dir` (inclusive) looking for any project marker.
    Returns the first directory containing a marker, or `dir` itself
    after at most 10 levels. -/
private partial def findProjectRoot (dir : System.FilePath) (depth : Nat := 10)
    : IO System.FilePath := do
  if depth = 0 then return dir
  for marker in projectMarkers do
    if ← (dir / marker).pathExists then return dir
  match dir.parent with
  | none => return dir
  | some parent =>
    if parent == dir then return dir
    findProjectRoot parent (depth - 1)

/-- Build the `--standard-json` input payload for a single `.sol` source. -/
private def buildStandardJsonInput (solPath : System.FilePath) : IO Json := do
  let content ← IO.FS.readFile solPath
  let solName := solPath.fileName.getD solPath.toString
  return Json.mkObj [
    ("language", Json.str "Solidity"),
    ("sources", Json.mkObj [
      (solName, Json.mkObj [
        ("content", Json.str content)
      ])
    ]),
    ("settings", Json.mkObj [
      ("outputSelection", Json.mkObj [
        ("*", Json.mkObj [
          ("", Json.arr #[Json.str "ast"])
        ])
      ])
    ])
  ]

/-- Invoke `solc --standard-json` on `solPath` and return the parsed JSON
    output (after enforcing that solc didn't return any fatal errors).

    Implementation mirrors `Tools/Solidity/src/solast.py:invoke_solc`. -/
def invokeSolc (solPath : System.FilePath) : IO (Except Error Json) := do
  let solPath ← IO.FS.realPath solPath
  let solDir := solPath.parent.getD "."
  let projectRoot ← findProjectRoot solDir
  let input ← buildStandardJsonInput solPath
  let inputStr := input.compress
  -- Pipe the standard-json input via stdin, capture stdout.
  let child ← IO.Process.spawn {
    cmd := "solc",
    args := #["--standard-json",
              "--base-path", solDir.toString,
              "--allow-paths", projectRoot.toString],
    stdin := .piped, stdout := .piped, stderr := .piped
  }
  let (childStdin, child) ← child.takeStdin
  childStdin.putStr inputStr
  childStdin.flush
  -- Closing stdin signals EOF to solc.
  let stdout ← child.stdout.readToEnd
  let stderr ← child.stderr.readToEnd
  let exit ← child.wait
  if exit != 0 then return .error (.exitCode exit stderr)
  match Json.parse stdout with
  | .error e => return .error (.invalidJson e)
  | .ok j =>
    -- Reject fatal diagnostics. Warnings (severity != "error") are tolerated.
    let errors := (j.getObjVal? "errors").toOption.getD (Json.arr #[])
    let fatals : Array String := match errors with
      | Json.arr elems =>
        elems.filterMap fun e =>
          match (e.getObjVal? "severity").toOption with
          | some (Json.str "error") =>
            (e.getObjVal? "formattedMessage").toOption.bind fun fm =>
              match fm with
              | Json.str s => some s
              | _ => none
          | _ => none
      | _ => #[]
    if fatals.isEmpty then return .ok j
    else return .error (.fatalDiagnostics fatals)

/-- Extract the AST node from solc's standard-json output. solc returns
    `{"sources": {"<file>": {"ast": <node>}}}`; we return the first AST
    we find, matching `solast.py:get_ast`. -/
def getAst (solcOutput : Json) : Except Error Json :=
  match (solcOutput.getObjVal? "sources").toOption with
  | none => .error .noAst
  | some sources =>
    match sources with
    | Json.obj entries =>
      let asts : Array Json := entries.toArray.filterMap fun (_name, info) =>
        (info.getObjVal? "ast").toOption
      match asts.toList with
      | [] => .error .noAst
      | a :: _ => .ok a
    | _ => .error .noAst

/-- One-shot helper: invoke solc on `solPath` and return the AST `Json`. -/
def parseFile (solPath : System.FilePath) : IO (Except Error Json) := do
  match ← invokeSolc solPath with
  | .error e => return .error e
  | .ok output => return getAst output

end Strata.Solidity.Solc

end
