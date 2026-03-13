/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

import Lean.Data.Json
import Strata.Languages.Core.Verifier
import Strata.DL.Imperative.MetaData

open Lean (Json toJson)
open Core (VCResult Outcome)

namespace StrataSolidity.Sarif

/-- Strip internal suffixes from variable names for readability. -/
def cleanVarName (name : String) : String :=
  let s := name
  let s := if s.startsWith "self." then s.drop 5 else s
  let s := if s.endsWith "_param" then s.dropRight 6 else s
  let s := if s.endsWith "_in" then s.dropRight 3 else s
  let s := s.replace "__" "."
  s

private def mkRule (id desc : String) : Json :=
  Json.mkObj [
    ("id", Json.str id),
    ("shortDescription", Json.mkObj [("text", Json.str desc)])
  ]

private def ruleDefinitions : Array Json := #[
  mkRule "strata/ensures-fail" "Postcondition violation",
  mkRule "strata/requires-fail" "Precondition violation",
  mkRule "strata/invariant-fail" "Contract invariant violation",
  mkRule "strata/assert-fail" "Assertion violation",
  mkRule "strata/unknown" "Verification inconclusive"
]

private def classifyRule (label : String) : String × Nat :=
  let l := label.toLower
  if (l.splitOn "ensures").length > 1 then ("strata/ensures-fail", 0)
  else if (l.splitOn "requires").length > 1 then ("strata/requires-fail", 1)
  else if (l.splitOn "invariant").length > 1 then ("strata/invariant-fail", 2)
  else if (l.splitOn "assert").length > 1 then ("strata/assert-fail", 3)
  else ("strata/unknown", 4)

private def simpleHash (s : String) : String :=
  let h := s.foldl (fun acc c => acc * 31 + c.toNat) 7
  toString h

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

private def resultMessage (label : String) (o : Outcome) : String :=
  match o with
  | .pass => s!"{label}: pass"
  | .fail => s!"{label}: fail"
  | .unknown => s!"{label}: unknown"
  | .implementationError e => s!"{label}: implementation error: {e}"

private def vcResultToJson (vcr : VCResult) (sourceOpt : Option (String × String)) : Json :=
  let label := vcr.obligation.label
  let (ruleId, ruleIdx) := classifyRule label
  let level := resultLevel vcr.result
  let kind := resultKind vcr.result
  let msg := resultMessage label vcr.result
  let base : Array (String × Json) := #[
    ("ruleId", Json.str ruleId),
    ("ruleIndex", toJson ruleIdx),
    ("level", Json.str level),
    ("kind", Json.str kind),
    ("message", Json.mkObj [("text", Json.str msg)]),
    ("partialFingerprints", Json.mkObj [("obligationLabel/v1", Json.str (simpleHash label))])
  ]
  let locations := match Imperative.getFileRange vcr.obligation.metadata with
    | some fr =>
      if fr.range.isNone then #[]
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
        #[Json.mkObj [
          ("physicalLocation", Json.mkObj [
            ("artifactLocation", Json.mkObj [("uri", Json.str uri)]),
            ("region", Json.mkObj [
              ("startLine", toJson line),
              ("startColumn", toJson (col + 1))
            ])
          ])
        ]]
    | none => #[]
  let fields := if locations.isEmpty then base
    else base.push ("locations", Json.arr locations)
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
          ("rules", Json.arr ruleDefinitions)
        ])
      ]),
      ("results", Json.arr results)
    ]])
  ]
  sarif.pretty
