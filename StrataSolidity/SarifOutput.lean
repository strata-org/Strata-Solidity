/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

import Lean.Data.Json
import Strata.Languages.Core.Verifier
import Strata.DL.Imperative.MetaData
import StrataSolidity.SolcAstParser
import StrataSolidity.Obligations

open Lean (Json toJson)
open Core (VCResult VCOutcome VCError)

namespace StrataSolidity.Sarif

private def mkRule (id desc : String) : Json :=
  Json.mkObj [
    ("id", Json.str id),
    ("shortDescription", Json.mkObj [("text", Json.str desc)])
  ]

/-- Rule ids, in `ruleIndex` order. Indices 0–4 are kept stable for existing
    consumers; new rules are appended. A rule names the kind of property
    checked; the result's `kind`/`level` say whether it held. -/
private def rules : Array (String × String) := #[
  ("strata/ensures-fail", "Postcondition"),
  ("strata/requires-fail", "Precondition"),
  ("strata/invariant-fail", "Contract invariant"),
  ("strata/assert-fail", "Assertion"),
  ("strata/unknown", "Other verification condition"),
  ("strata/frame-fail", "Modifies (frame) condition"),
  ("strata/loop-invariant-fail", "Loop invariant"),
  ("strata/division-by-zero", "Division or modulus by zero"),
  ("strata/not-verified", "Annotation or function not verified"),
  ("strata/tool-error", "Verification error")
]

private def ruleDefinitions : Array Json := rules.map fun (id, desc) => mkRule id desc

private def ruleIdx (id : String) : Nat :=
  (rules.findIdx? (·.1 == id)).getD 4

/-- What kind of property an obligation checks. Uses the property summary
    the translator and Laurel attach (`ensures …`, `invariant #n`,
    `modifies frame (…)`, `precondition`, …), falling back to the label for
    obligations that carry none (loop invariants, user `assert`s). -/
private def classifyRule (vcr : VCResult) : String :=
  let summary := (vcr.obligation.metadata.getPropertySummary.getD "").toLower
  let label := vcr.obligation.label.toLower
  let has (s sub : String) := (s.splitOn sub).length > 1
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
  else if label.startsWith "assert" && (summary.isEmpty || summary.startsWith "assert") then
    -- (An `assert` in an inherited function carries its text and the
    -- contract it is verified in as summary.)
    "strata/assert-fail"
  else "strata/unknown"

/-- How an obligation came out, shared by every output format. -/
inductive Verdict where
  | pass
  | fail
  /-- Neither proven nor refuted, including solver timeouts. -/
  | unknown
  /-- An encoding error or solver crash: nothing was checked. -/
  | error (msg : String)

/-- `VCResult.isSuccess` / `isFailure` decide pass and fail. A solver
    timeout is `unknown`, as upstream Core classifies it; an encoding error
    or a solver crash is an `error`. -/
def verdict (vcr : VCResult) : Verdict :=
  match vcr.outcome with
  | .error e => if vcr.isTimeout then .unknown else .error (toString e)
  | .ok _ =>
    if vcr.isSuccess then .pass
    else if vcr.isFailure then .fail
    else .unknown

/-- SARIF `(kind, level)`. SARIF 2.1.0 §3.27.9–10 allow a level other than
    `none` only with kind `fail`, so everything that needs attention —
    refuted, not proven, not checked — is a `fail` whose level tells them
    apart; proven obligations are `pass` with level `none`. -/
private def kindAndLevel : Verdict → String × String
  | .pass => ("pass", "none")
  | .fail => ("fail", "error")
  | .unknown => ("fail", "warning")
  | .error _ => ("fail", "error")

/-- `<obligation name>: <verdict>`. -/
private def resultMessage (vcr : VCResult) (sourceOpt : Option (String × String)) : Verdict → String :=
  let name := StrataSolidity.Obligations.name vcr sourceOpt
  fun
  | .pass => s!"{name}: pass"
  | .fail => s!"{name}: fail"
  | .unknown => s!"{name}: unknown"
  | .error e => s!"{name}: verification error: {e}"

/-- An RFC 3986 URI reference for a file path: percent-encoded, with a
    `file://` scheme for absolute paths (SARIF §3.10). -/
def pathToUri (path : String) : String :=
  let unreserved (c : Char) : Bool :=
    c.isAlphanum || c == '-' || c == '.' || c == '_' || c == '~' || c == '/'
  let hex (n : Nat) : String :=
    let d := "0123456789ABCDEF".toList
    String.ofList [d[n / 16]!, d[n % 16]!]
  let encoded := String.join (path.toList.map fun c =>
    if unreserved c then c.toString
    else String.join (c.toString.toUTF8.toList.map fun b => "%" ++ hex b.toNat))
  if path.startsWith "/" then "file://" ++ encoded else encoded

/-- A SARIF physical location in `path`, with a region when known. -/
private def physicalLocation (path : String) (region : Option (Nat × Nat)) : Json :=
  let artifact := Json.mkObj [("uri", Json.str (pathToUri path))]
  Json.mkObj [("physicalLocation", Json.mkObj (
    [("artifactLocation", artifact)] ++
    match region with
    | some (line, col) => [("region", Json.mkObj [
        ("startLine", toJson line), ("startColumn", toJson (col + 1))])]
    | none => []))]

/-- FNV-1a (64-bit) of `s`, as 16 hex digits. -/
private def fnv1a64 (s : String) : String :=
  let h := s.toUTF8.foldl (fun (h : UInt64) b => (h ^^^ b.toUInt64) * 0x100000001b3)
    (0xcbf29ce484222325 : UInt64)
  let digits := (Nat.toDigits 16 h.toNat)
  String.ofList (List.replicate (16 - digits.length) '0' ++ digits)

/-- What identifies an obligation across edits: its rule, its procedure
    (`procName`; the function), and its property summary, else the source
    text it checks (`assert(x > 0)`), else its label with digits (byte
    offsets, counters) removed — never a position in the file. Results that
    share one are told apart by their ordinal. -/
private def identity (ruleId procName : String) (vcr : VCResult)
    (sourceOpt : Option (String × String)) : String :=
  let sourceText : Option String :=
    match Imperative.getFileRange vcr.obligation.metadata, sourceOpt with
    | some { file := .file path, range }, some (srcPath, srcText) =>
      if path == srcPath && !range.isNone then
        some (String.fromUTF8! (srcText.toUTF8.extract range.start.byteIdx range.stop.byteIdx))
      else none
    | _, _ => none
  let name := vcr.obligation.metadata.getPropertySummary.getD
    (sourceText.getD (String.ofList (vcr.obligation.label.toList.filter (!·.isDigit))))
  s!"{ruleId}|{procName}|{name}"

private def vcResultToJson (vcr : VCResult) (procName : String)
    (sourceOpt : Option (String × String)) (ordinal : Nat) : Json :=
  let ruleId :=
    match verdict vcr with
    | .error _ => "strata/tool-error"
    | _ => classifyRule vcr
  let v := verdict vcr
  let (kind, level) := kindAndLevel v
  let fingerprint := fnv1a64 s!"{identity ruleId procName vcr sourceOpt}|{ordinal}"
  let base : Array (String × Json) := #[
    ("ruleId", Json.str ruleId),
    ("ruleIndex", toJson (ruleIdx ruleId)),
    ("level", Json.str level),
    ("kind", Json.str kind),
    ("message", Json.mkObj [("text", Json.str (resultMessage vcr sourceOpt v))]),
    ("partialFingerprints", Json.mkObj [("obligationId/v2", Json.str fingerprint)])
  ]
  -- Every result gets a location (code scanning drops results without one):
  -- the obligation's region when it has one in the user's file, else the
  -- user's file (or the obligation's own file) without a region.
  let location : Option Json :=
    match Imperative.getFileRange vcr.obligation.metadata, sourceOpt with
    | some { file := .file path, range }, some (srcPath, srcText) =>
      if path == srcPath && !range.isNone then
        let pos := (Lean.FileMap.ofString srcText).toPosition range.start
        some (physicalLocation srcPath (some (pos.line, pos.column)))
      else if path == srcPath || range.isNone then some (physicalLocation srcPath none)
      else some (physicalLocation path none)
    | _, some (srcPath, _) => some (physicalLocation srcPath none)
    | some { file := .file path, .. }, none => some (physicalLocation path none)
    | none, none => none
  let fields := match location with
    | some l => base.push ("locations", Json.arr #[l])
    | none => base
  Json.mkObj fields.toList

/-- A SARIF result for something the translator did not verify (see
    `Strata.Solidity.TranslationWarning`), located at byte offset `start`.
    It needs attention, so it is a `fail` with level `warning`. -/
private def warningToJson (sourceOpt : Option (String × String))
    (warning : String.Pos.Raw × String) (ordinal : Nat) : Json :=
  let (start, message) := warning
  let base : List (String × Json) := [
    ("ruleId", Json.str "strata/not-verified"),
    ("ruleIndex", toJson (ruleIdx "strata/not-verified")),
    ("level", Json.str "warning"),
    ("kind", Json.str "fail"),
    ("message", Json.mkObj [("text", Json.str message)]),
    ("partialFingerprints", Json.mkObj [
      ("obligationId/v2", Json.str (fnv1a64 s!"strata/not-verified|{message}|{ordinal}"))])
  ]
  match sourceOpt with
  | some (srcPath, srcText) =>
    let pos := (Lean.FileMap.ofString srcText).toPosition start
    Json.mkObj (base ++ [("locations", Json.arr #[physicalLocation srcPath (some (pos.line, pos.column))])])
  | none => Json.mkObj base

/-- Number each item by how many earlier items share its key. -/
private def ordinals {α} (xs : Array α) (key : α → String) : Array (α × Nat) := Id.run do
  let mut seen : Std.HashMap String Nat := {}
  let mut out := #[]
  for x in xs do
    let k := key x
    let n := seen.getD k 0
    seen := seen.insert k (n + 1)
    out := out.push (x, n)
  return out

/-- A SARIF 2.1.0 document with the given results. -/
private def sarifDocument (results : Array Json) : String :=
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
      -- Columns are counted in Unicode code points (Lean's `FileMap`).
      ("columnKind", Json.str "unicodeCodePoints"),
      ("results", Json.arr results)
    ]])
  ]
  sarif.pretty

/-- Convert VCResults, each with the name of its procedure (`""` if
    unknown), to a SARIF 2.1.0 JSON string. `warnings` are (byte offset,
    message) pairs for unverified annotations/functions. -/
def toSarif (vcResults : Array (VCResult × String)) (sourceOpt : Option (String × String))
    (warnings : List (String.Pos.Raw × String) := []) : String :=
  let ruleOf (vcr : VCResult) := match verdict vcr with
    | .error _ => "strata/tool-error"
    | _ => classifyRule vcr
  sarifDocument <|
    (ordinals vcResults (fun (vcr, p) => identity (ruleOf vcr) p vcr sourceOpt)).map
      (fun ((vcr, p), n) => vcResultToJson vcr p sourceOpt n) ++
    (ordinals warnings.toArray (·.2)).map (fun (w, n) => warningToJson sourceOpt w n)

/-- The SARIF document for a run that could not verify `path` at all (it
    did not parse or translate): one `strata/tool-error` result, so that a
    CI upload still shows why. -/
def failureSarif (path message : String) : String :=
  sarifDocument #[Json.mkObj [
    ("ruleId", Json.str "strata/tool-error"),
    ("ruleIndex", toJson (ruleIdx "strata/tool-error")),
    ("level", Json.str "error"),
    ("kind", Json.str "fail"),
    ("message", Json.mkObj [("text", Json.str message)]),
    ("partialFingerprints", Json.mkObj [
      ("obligationId/v2", Json.str (fnv1a64 s!"strata/tool-error|{message}"))]),
    ("locations", Json.arr #[physicalLocation path none])]]
