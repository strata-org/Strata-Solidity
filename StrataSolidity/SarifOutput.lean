/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

import Lean.Data.Json
import Strata.Languages.Core.Verifier
import Strata.DL.Imperative.MetaData
import StrataSolidity.SolcAstParser

open Lean (Json toJson)
open Core (VCResult VCOutcome VCError)

namespace StrataSolidity.Sarif

/-- Strip internal suffixes from variable names for readability. -/
def cleanVarName (name : String) : String :=
  let s := name
  let s := if s.startsWith "self." then (s.drop 5).toString else s
  let s := if s.endsWith "_param" then (s.dropEnd 6).toString else s
  let s := if s.endsWith "_in" then (s.dropEnd 3).toString else s
  let s := s.replace "__" "."
  Strata.Solidity.SolcAst.unmangleName s

private def mkRule (id desc : String) : Json :=
  Json.mkObj [
    ("id", Json.str id),
    ("shortDescription", Json.mkObj [("text", Json.str desc)])
  ]

/-- Rule ids, in `ruleIndex` order. Indices 0–4 are kept stable for existing
    consumers; new rules are appended. -/
private def rules : Array (String × String) := #[
  ("strata/ensures-fail", "Postcondition violation"),
  ("strata/requires-fail", "Precondition violation"),
  ("strata/invariant-fail", "Contract invariant violation"),
  ("strata/assert-fail", "Assertion violation"),
  ("strata/unknown", "Verification inconclusive"),
  ("strata/frame-fail", "Modifies (frame) violation"),
  ("strata/loop-invariant-fail", "Loop invariant violation"),
  ("strata/division-by-zero", "Division or modulus by zero")
]

private def ruleDefinitions : Array Json := rules.map fun (id, desc) => mkRule id desc

private def ruleIdx (id : String) : Nat :=
  (rules.findIdx? (·.1 == id)).getD 4

/-- What kind of property an obligation checks. Uses the property summary
    the translator and Laurel attach (`ensures …`, `invariant #n`,
    `modifies frame (…)`, `precondition`, …), falling back to the label for
    obligations that carry none (loop invariants, user `assert`s). -/
private def classifyRule (vcr : VCResult) : String × Nat :=
  let summary := (vcr.obligation.metadata.getPropertySummary.getD "").toLower
  let label := vcr.obligation.label.toLower
  let has (s sub : String) := (s.splitOn sub).length > 1
  let id :=
    if summary.startsWith "ensures" then "strata/ensures-fail"
    else if summary.startsWith "invariant" then "strata/invariant-fail"
    else if summary.startsWith "modifies" then "strata/frame-fail"
    -- Call-site checks of a callee's preconditions, including those of its
    -- modifiers and the translator's `axiom`s.
    else if ["requires", "precondition", "modifier precondition", "axiom"].any (fun (p : String) => summary.startsWith p) then
      "strata/requires-fail"
    -- Laurel's checks of its division and modulus.
    else if summary == "divisor is non-zero" || summary == "modulus is non-zero" then
      "strata/division-by-zero"
    else if has label "loopinv" then "strata/loop-invariant-fail"
    else "strata/assert-fail"
  (id, ruleIdx id)

private def simpleHash (s : String) : String :=
  let h := s.foldl (fun acc c => acc * 31 + c.toNat) 7
  toString h

/-- Verdict for SARIF reporting. Uses the same predicates as the CLI's text
    and JSON output (`VCResult.isSuccess` / `isFailure`), so all formats
    agree. Solver or encoding errors are reported as failures: nothing was
    proven. -/
private inductive Verdict where
  | pass
  | fail
  | unknown
  | error (msg : String)

private def classifyOutcome (vcr : VCResult) : Verdict :=
  match vcr.outcome with
  | .error e => .error (toString e)
  | .ok _ =>
    if vcr.isSuccess then .pass
    else if vcr.isFailure then .fail
    else .unknown

private def resultLevel : Verdict → String
  | .fail | .error _ => "error"
  | .pass => "none"
  | .unknown => "warning"

private def resultKind : Verdict → String
  | .fail | .error _ => "fail"
  | .pass => "pass"
  | .unknown => "open"

/-- `<summary or label>: <verdict>`. -/
private def resultMessage (vcr : VCResult) : Verdict → String :=
  let name := vcr.obligation.metadata.getPropertySummary.getD vcr.obligation.label
  fun
  | .pass => s!"{name}: pass"
  | .fail => s!"{name}: fail"
  | .unknown => s!"{name}: unknown"
  | .error e => s!"{name}: implementation error: {e}"

private def vcResultToJson (vcr : VCResult) (sourceOpt : Option (String × String)) : Json :=
  let label := vcr.obligation.label
  let (ruleId, ruleIdx) := classifyRule vcr
  let verdict := classifyOutcome vcr
  let level := resultLevel verdict
  let kind := resultKind verdict
  let msg := resultMessage vcr verdict
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
