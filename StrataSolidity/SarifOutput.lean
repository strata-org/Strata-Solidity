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

private def resultLevel (o : Outcome) : String :=
  match o with
  | .fail | .implementationError _ => "error"
  | .pass => "none"
  | .unknown => "warning"

private def resultMessage (label : String) (o : Outcome) : String :=
  match o with
  | .pass => s!"{label}: pass"
  | .fail => s!"{label}: fail"
  | .unknown => s!"{label}: unknown"
  | .implementationError e => s!"{label}: implementation error: {e}"

private def vcResultToJson (vcr : VCResult) (sourceOpt : Option (String × String)) : Json :=
  let label := vcr.obligation.label
  let level := resultLevel vcr.result
  let msg := resultMessage label vcr.result
  let base := #[
    ("ruleId", Json.str label),
    ("level", Json.str level),
    ("message", Json.mkObj [("text", Json.str msg)])
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
          ("version", Json.str "0.1.0")
        ])
      ]),
      ("results", Json.arr results)
    ]])
  ]
  sarif.pretty
