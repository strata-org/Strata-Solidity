/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

import Lean.Data.Json
import Strata.Languages.Core.Verifier
import Strata.DL.Imperative.MetaData

open Lean (Json toJson)
open Core (VCResult Outcome LExprModel)

namespace StrataSolidity.Sarif

/-- Strip internal suffixes from variable names for readability. -/
def cleanVarName (name : String) : String :=
  let s := name
  let s := if s.startsWith "self." then s.drop 5 else s
  let s := if s.endsWith "_param" then s.dropRight 6 else s
  let s := if s.endsWith "_local" then s.dropRight 6 else s
  let s := if s.endsWith "_ret" then s.dropRight 4 else s
  let s := if s.endsWith "_in" then s.dropRight 3 else s
  let s := s.replace "__" "."
  -- Strip trailing _N (SSA numeric suffixes)
  let s := match s.revPosOf '_' with
    | some idx =>
      let suffix := s.drop (idx.byteIdx + 1)
      if suffix.isEmpty then s
      else if suffix.all Char.isDigit then s.take idx.byteIdx
      else s
    | none => s
  s

/-- Format counterexample model entries for SARIF message text. -/
private def formatCounterexample (cex : LExprModel) : String :=
  if cex.isEmpty then ""
  else
    let entries := cex.map fun (id, e) =>
      let name := cleanVarName (toString id)
      let val := toString (Core.formatExprs [e])
      s!"  {name} = {val}"
    "\nCounterexample:\n" ++ "\n".intercalate entries

private def resultLevel (o : Outcome) : String :=
  match o with
  | .fail | .implementationError _ => "error"
  | .pass => "none"
  | .unknown => "warning"

private def resultKind (o : Outcome) : String :=
  match o with
  | .fail | .implementationError _ => "fail"
  | .pass => "pass"
  | .unknown => "open"

/-- Rule definitions for common verification results. -/
private def ruleDefinitions : Array (String × String × String) := #[
  ("strata/ensures-fail", "Postcondition violation", "A postcondition (ensures clause) could not be verified."),
  ("strata/requires-fail", "Precondition violation", "A precondition (requires clause) could not be verified."),
  ("strata/invariant-fail", "Contract invariant violation", "A contract invariant could not be verified."),
  ("strata/assert-fail", "Assertion violation", "An assertion could not be verified."),
  ("strata/unknown", "Verification inconclusive", "The verifier could not determine the result.")
]

private def rulesJson : Json :=
  Json.arr <| ruleDefinitions.map fun (id, name, desc) =>
    Json.mkObj [
      ("id", Json.str id),
      ("name", Json.str name),
      ("shortDescription", Json.mkObj [("text", Json.str name)]),
      ("fullDescription", Json.mkObj [("text", Json.str desc)])
    ]

/-- Map an obligation label to a ruleId and ruleIndex. -/
private def classifyRule (label : String) : String × Nat :=
  let l := label.toLower
  if l.containsSubstr "ensures" then ("strata/ensures-fail", 0)
  else if l.containsSubstr "requires" then ("strata/requires-fail", 1)
  else if l.containsSubstr "invariant" then ("strata/invariant-fail", 2)
  else if l.containsSubstr "assert" then ("strata/assert-fail", 3)
  else ("strata/unknown", 4)

/-- Simple hash of a string for fingerprinting. -/
private def simpleHash (s : String) : String :=
  let h := s.foldl (fun acc c => acc * 31 + c.toNat) 7
  let hex := Nat.toDigits 16 h |>.map fun d =>
    if d < 10 then Char.ofNat (d + '0'.toNat) else Char.ofNat (d - 10 + 'a'.toNat)
  String.mk hex

private def resultMessage (label : String) (o : Outcome) (cex : LExprModel) : String :=
  let base := match o with
    | .pass => s!"{label}: pass"
    | .fail => s!"{label}: fail"
    | .unknown => s!"{label}: unknown"
    | .implementationError e => s!"{label}: implementation error: {e}"
  match o with
  | .fail => base ++ formatCounterexample cex
  | _ => base

private def vcResultToJson (vcr : VCResult) (sourceOpt : Option (String × String)) : Json :=
  let label := vcr.obligation.label
  let level := resultLevel vcr.result
  let kind := resultKind vcr.result
  let (ruleId, ruleIdx) := classifyRule label
  let msg := resultMessage label vcr.result vcr.lexprModel
  let fingerprint := simpleHash label
  let base := #[
    ("ruleId", Json.str ruleId),
    ("ruleIndex", toJson ruleIdx),
    ("level", Json.str level),
    ("kind", Json.str kind),
    ("message", Json.mkObj [("text", Json.str msg)]),
    ("partialFingerprints", Json.mkObj [("obligationLabel/v1", Json.str fingerprint)])
  ]
  let (locations, relatedLocations) := match Imperative.getFileRange vcr.obligation.metadata with
    | some fr =>
      if fr.range.isNone then (#[], #[])
      else
        let uri := match fr.file with | .file path => path
        let (line, col) := match sourceOpt with
          | some (srcPath, srcText) =>
            match fr.file with
            | .file path =>
              if path == srcPath then
                let pos := (Lean.FileMap.ofString srcText).toPosition fr.range.start
                (pos.line, pos.column)
              else (1, 0)
          | none => (1, 0)
        let loc := Json.mkObj [
          ("physicalLocation", Json.mkObj [
            ("artifactLocation", Json.mkObj [("uri", Json.str uri)]),
            ("region", Json.mkObj [
              ("startLine", toJson line),
              ("startColumn", toJson (col + 1))
            ])
          ])
        ]
        let related := Json.mkObj [
          ("id", toJson (0 : Nat)),
          ("message", Json.mkObj [("text", Json.str "function location")]),
          ("physicalLocation", Json.mkObj [
            ("artifactLocation", Json.mkObj [("uri", Json.str uri)]),
            ("region", Json.mkObj [("startLine", toJson line)])
          ])
        ]
        (#[loc], #[related])
    | none => (#[], #[])
  let fields := if locations.isEmpty then base
    else base.push ("locations", Json.arr locations)
      |>.push ("relatedLocations", Json.arr relatedLocations)
  Json.mkObj fields.toList

/-- Convert an array of VCResults to a SARIF 2.1.0 JSON string. -/
def toSarif (vcResults : Array VCResult) (sourceOpt : Option (String × String)) : String :=
  let results := vcResults.map (vcResultToJson · sourceOpt)
  let sarif := Json.mkObj [
    ("$schema", Json.str "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json"),
    ("version", Json.str "2.1.0"),
    ("runs", Json.arr #[Json.mkObj [
      ("tool", Json.mkObj [
        ("driver", Json.mkObj [
          ("name", Json.str "StrataSolidity"),
          ("version", Json.str "0.1.0"),
          ("rules", rulesJson)
        ])
      ]),
      ("results", Json.arr results)
    ]])
  ]
  sarif.pretty
