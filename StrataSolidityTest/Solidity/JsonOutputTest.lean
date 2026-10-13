/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

/-
  Characterization tests for the CLI output shapes of `strataSolidity`.

  This module hosts the Lean-side PBT / characterization coverage for
  `REQ-PBT-005` (`--json` shape) and `REQ-PBT-006` (`--pipeline-json`
  shape). It is driven by `Strata.Solidity.Test.Pbt` (see
  `PbtHarness.lean`) for shared configuration and helpers.

  ## Task 2.6 — REQ-PBT-005: `--json` shape

  Property (from `requirements.md` §13 REQ-PBT-005):
    For every element of the `--json` output array, the object has
      * `name : String`,
      * `status ∈ {"pass","fail","unknown","implementation_error","not_verified"}`
        (`not_verified`: an annotation or function that is not verified,
        one entry per warning),
      * `line` and `col` are either BOTH present (and both `Nat`) or
        BOTH absent — no mixed case allowed.

  ### How the test is driven

  The task description (tasks.md §2.6) prescribes a Plausible property
  whose generator is `Gen.elements fixtures`, that invokes
  `strataSolidity --json <ion>` per fixture and checks the invariants on
  every array element. The task also allows a concrete downgrade:
  "If invoking an external process from a Plausible test turns out to be
  impractical (binary not built, fixtures missing), downgrade to a
  non-Plausible `#eval` test that loops over the fixture list and performs
  the same assertions. Cite the downgrade in the module docstring."

  **Downgrade rationale (cited per task 2.6).** Plausible properties are
  pure `Prop`s checked over a generator; they cannot thread `IO` through
  the `Testable` machinery. We additionally need to invoke the
  external `strataSolidity` binary per fixture. Both concerns make a
  true Plausible property impractical
  in this harness today. Accordingly, this module loops over a curated
  fixture matrix in `#eval` blocks and performs *the same assertions* the
  task prescribes on every JSON element, using `Lean.Json.parse` for
  decoding. The Plausible-flavored structure is preserved: there is a
  single fixture list (`jsonFixtureMatrix`) that plays the role of
  `Gen.elements fixtures`, and the per-element predicate
  (`isValidJsonElement`) is pure and would directly become the Plausible
  property body once an IO-friendly `Testable` instance is available.

  ### Robustness

  If the `strataSolidity` binary is not built or the `Strata` submodule
  is not initialized, the setup helpers return a `.error` outcome and the `#eval`
  asserts fail with an actionable message rather than silently skipping.
  This is deliberate: characterization tests must fail loud when the
  pipeline under test is unavailable.

  ### File layout

  This module now hosts two properties, in sequence:
    * `section JsonShape` — REQ-PBT-005, the `--json` array-element shape.
    * `section PipelineJsonShape` — REQ-PBT-006, the `--pipeline-json`
      object shape (top-level keys, obligation keys, summary keys).

  Both sections share the helpers in `section Setup`; the `--json` and
  `--pipeline-json` CLI invocations differ only in the flag passed to the
  `strataSolidity` binary.

  Realizes: REQ-PBT-005, REQ-PBT-006, REQ-OUT-020..REQ-OUT-023,
  REQ-OUT-040..REQ-OUT-045, REQ-CLI-012, REQ-CLI-013, REQ-CLI-022,
  REQ-CLI-023, REQ-CLI-040.
-/
import Lean.Data.Json
import StrataSolidityTest.Solidity.PbtHarness

namespace Strata.Solidity.Test.JsonOutput

open Lean (Json)
open Strata.Solidity.Test.Pbt

/-! ## section Setup

    Locating the binary, generating Ion files, and invoking
    `strataSolidity --json`. All helpers here are shared with task 2.7's
    `--pipeline-json` test.
-/
section Setup

/-- Repo-relative paths used by the test. All are anchored at the project
    root so the test works under `lake test` no matter where the script
    is invoked from. -/
structure TestPaths where
  /-- Absolute path to the StrataSolidity project root
      (inferred by walking up from `StrataSolidityTest/Solidity/`). -/
  projectRoot : System.FilePath
  /-- Absolute path to the built `strataSolidity` binary. The binary
      invokes solc and parses its JSON AST directly (in-Lean frontend);
      no Python or Ion step is involved. -/
  binary : System.FilePath

/-- Resolve the repo-relative paths by walking upward from CWD until we
    find a Lake manifest (`lakefile.lean` or `lakefile.toml`). Falls back
    to CWD itself if not found. The project uses `lakefile.lean` today;
    `lakefile.toml` is checked as well so the helper is robust to either
    Lake config flavour. -/
private partial def findProjectRoot : IO System.FilePath := do
  let rec go (p : System.FilePath) (fuel : Nat) : IO System.FilePath := do
    if fuel = 0 then return p
    if (← (p / "lakefile.lean").pathExists) ||
       (← (p / "lakefile.toml").pathExists) then
      return p
    else
      match p.parent with
      | some parent => go parent (fuel - 1)
      | none => return p
  go (← IO.currentDir) 10

/-- Construct a fully resolved `TestPaths` from the current working
    directory. The caller is responsible for handling the case where the
    binary or the dialect file is missing. -/
def mkTestPaths : IO TestPaths := do
  let root ← findProjectRoot
  return {
    projectRoot := root
    binary := root / ".lake" / "build" / "bin" / "strataSolidity"
  }

/-- Outcome of running the test pipeline for one fixture. -/
inductive RunResult where
  /-- Pipeline ran to completion; `stdout` is the `--json` output. -/
  | ok (stdout : String)
  /-- Pipeline setup or execution failed; `reason` explains. -/
  | error (reason : String)
  deriving Inhabited

/-- Invoke `strataSolidity <sol> --json` and return its stdout. The
    binary runs the in-Lean frontend (solc → typed AST) itself; source
    positions come from the input file, exercising the "both present /
    both absent" branch of REQ-PBT-005. -/
def runStrataJson (paths : TestPaths) (solPath : System.FilePath) : IO String := do
  let out ← IO.Process.output {
    cmd := paths.binary.toString
    args := #[
      solPath.toString,
      "--json"
    ]
  }
  if out.exitCode != 0 then
    throw <| IO.userError
      s!"strataSolidity --json failed (exit {out.exitCode}):\nstderr:\n{out.stderr}"
  return out.stdout

/-- Drive the pipeline end-to-end for one Solidity fixture: invoke
    `strataSolidity <sol> --json` (the binary runs solc + the in-Lean
    frontend itself). Returns the `--json` stdout or an error string. -/
def runFixtureJson (paths : TestPaths) (fixtureName : String) : IO RunResult := do
  if !(← paths.binary.pathExists) then
    return .error s!"strataSolidity binary not found at {paths.binary}. Run `lake build` first."
  let solPath := paths.projectRoot / "StrataSolidityTest" / "Solidity" / "tests" / s!"{fixtureName}.sol"
  if !(← solPath.pathExists) then
    return .error s!"Fixture not found: {solPath}"
  try
    let stdout ← runStrataJson paths solPath
    return .ok stdout
  catch e =>
    return .error s!"{e}"

/-- Invoke `strataSolidity <ion> --pipeline-json [--sol-source=<sol>]` and
    return its stdout. Sibling of `runStrataJson` specialized to the
    `--pipeline-json` mode exercised by REQ-PBT-006.

    Per REQ-CLI-022, `--pipeline-json` preserves the SMT artifacts in a
    fixed directory (`/tmp/strata-pipeline-smt` by default, or
    `STRATA_SMT_DIR` when set); per REQ-CLI-023, the binary clears any
    stale `*.smt2` files from that directory before running. To isolate
    this test from concurrently-running runs and to keep
    `STRATA_SMT_DIR` hermetic per fixture, we allocate a per-invocation
    directory and export it via `STRATA_SMT_DIR`. -/
def runStrataPipelineJson (paths : TestPaths) (solPath : System.FilePath) : IO String := do
  let smtDir ← IO.FS.createTempDir
  let out ← IO.Process.output {
    cmd := paths.binary.toString
    args := #[
      solPath.toString,
      "--pipeline-json"
    ]
    env := #[("STRATA_SMT_DIR", some smtDir.toString)]
  }
  if out.exitCode != 0 then
    throw <| IO.userError
      s!"strataSolidity --pipeline-json failed (exit {out.exitCode}):\nstderr:\n{out.stderr}"
  return out.stdout

/-- Sibling of `runFixtureJson` for `--pipeline-json` (REQ-PBT-006).
    Any infrastructure failure (missing binary, missing fixture,
    non-zero exit) is surfaced as `.error` so the `#eval` below fails
    loud rather than silently skipping. -/
def runFixturePipelineJson (paths : TestPaths) (fixtureName : String) : IO RunResult := do
  if !(← paths.binary.pathExists) then
    return .error s!"strataSolidity binary not found at {paths.binary}. Run `lake build` first."
  let solPath := paths.projectRoot / "StrataSolidityTest" / "Solidity" / "tests" / s!"{fixtureName}.sol"
  if !(← solPath.pathExists) then
    return .error s!"Fixture not found: {solPath}"
  try
    let stdout ← runStrataPipelineJson paths solPath
    return .ok stdout
  catch e =>
    return .error s!"{e}"

end Setup

/-! ## section JsonShape

    Property 5 — `--json` shape, realizing REQ-PBT-005.

    The per-element predicate `isValidJsonElement` is the pure body of the
    property. The fixture matrix `jsonFixtureMatrix` plays the role of
    `Gen.elements fixtures` — a Plausible property would sample from it;
    the `#eval` below enumerates it deterministically.
-/
section JsonShape

/-- Legal values for the `status` field (REQ-PBT-005, REQ-OUT-022), plus
    `not_verified` for the entries that report an annotation or function
    that is not verified. -/
def allowedStatuses : List String :=
  ["pass", "fail", "unknown", "implementation_error", "not_verified"]

/-- The curated fixture matrix for REQ-PBT-005.

    Each fixture exercises a different axis of the `--json` shape:
      * `test_spec_basic` — mix of `pass` results with and without
        resolved source positions.
      * `test_assert_fail` — at least one `fail` result.
      * `test_spec_post_fail` — `ensures` postcondition failure; another
        `fail` path through the `--json` formatter.
      * `test_require_fail` — `requires` precondition failure.
      * `test_arithmetic` — mostly-passing arithmetic fixture; baseline
        "everything green" case.

    Chosen small and fast so the full pipeline (binary — which runs
    solc itself — + JSON parse) runs quickly under `lake test`. -/
def jsonFixtureMatrix : List String :=
  [ "test_spec_basic"
  , "test_assert_fail"
  , "test_spec_post_fail"
  , "test_require_fail"
  , "test_arithmetic"
  ]

/-- Plausible-style generator over the fixture matrix. Exposed for
    documentation / future promotion to a true Plausible property once an
    `IO`-friendly `Testable` instance is available. -/
def genJsonFixture : Plausible.Gen String :=
  Plausible.Gen.elements jsonFixtureMatrix (by decide)

/-- The per-element property body for REQ-PBT-005. Pure; takes a parsed
    JSON value that is expected to be an array element (an object) and
    returns `Except String Unit` with a human-readable error on failure.

    Checks, in order:
      1. Element is a JSON object.
      2. `name` exists and is a string.
      3. `status` exists, is a string, and is in `allowedStatuses`.
      4. `line` and `col` are either BOTH present (and both natural
         numbers) or BOTH absent. No mixed case allowed. -/
def isValidJsonElement (j : Json) : Except String Unit := do
  let obj ← j.getObj?
  -- (2) name : String
  let nameJ ← j.getObjVal? "name"
  let _name ← nameJ.getStr?
  -- (3) status : String ∈ allowedStatuses
  let statusJ ← j.getObjVal? "status"
  let status ← statusJ.getStr?
  if !allowedStatuses.contains status then
    throw s!"status {status} not in {allowedStatuses}"
  -- (4) line/col pairing invariant.
  let hasLine := obj.contains "line"
  let hasCol := obj.contains "col"
  match hasLine, hasCol with
  | false, false => pure ()
  | true, true =>
    let lineJ ← j.getObjVal? "line"
    let _line ← lineJ.getNat?
    let colJ ← j.getObjVal? "col"
    let _col ← colJ.getNat?
    pure ()
  | true, false =>
    throw "element has `line` but is missing `col`"
  | false, true =>
    throw "element has `col` but is missing `line`"

/-- The full-array property: parse the `--json` stdout and apply
    `isValidJsonElement` to every element. Returns an error message if
    the stdout is not a JSON array or any element fails the per-element
    predicate. -/
def isValidJsonArray (stdout : String) : Except String Unit := do
  let j ← Json.parse stdout
  let arr ← j.getArr?
  for elt in arr do
    match isValidJsonElement elt with
    | .ok () => pure ()
    | .error msg => throw s!"element {elt.compress} failed: {msg}"

/-- Helper for the `#eval` below: run the pipeline for one fixture and
    apply the property, printing a PASS / FAIL line either way. Returns a
    `Bool` so the outer loop can accumulate and fail loud at the end. -/
def checkFixture (paths : TestPaths) (fixtureName : String) : IO Bool := do
  match ← runFixtureJson paths fixtureName with
  | .error reason =>
    IO.eprintln s!"FAIL {fixtureName}: {reason}"
    return false
  | .ok stdout =>
    match isValidJsonArray stdout with
    | .ok () =>
      IO.println s!"PASS {fixtureName}"
      return true
    | .error msg =>
      IO.eprintln s!"FAIL {fixtureName}: {msg}\nstdout was:\n{stdout}"
      return false

/- The entry point. Loops over `jsonFixtureMatrix` and enforces the
   REQ-PBT-005 shape invariants on every fixture's JSON output.

   Using `assert!` ensures this `#eval` aborts with a non-zero exit
   status on any failure, which propagates through `lake test`. -/
#eval show IO Unit from do
  let paths ← mkTestPaths
  let mut allOk := true
  for fixture in jsonFixtureMatrix do
    let ok ← checkFixture paths fixture
    allOk := allOk && ok
  assert! allOk

/-! Sanity checks on the pure predicate itself — make sure a
    well-formed object passes and every failure mode is caught. These
    are unit-level reinforcements of the property body and run at elab
    time without invoking the binary. -/

private def isOk : Except String Unit → Bool
  | .ok _ => true
  | .error _ => false

private def isErr : Except String Unit → Bool
  | .ok _ => false
  | .error _ => true

-- Well-formed: name + status, no position.
#guard isOk (isValidJsonElement
  (Json.mkObj [("name", .str "x"), ("status", .str "pass")]))

-- Well-formed: name + status + line + col.
#guard isOk (isValidJsonElement
  (Json.mkObj [("name", .str "x"), ("status", .str "fail"),
               ("line", .num 10), ("col", .num 4)]))

-- All five statuses accepted.
#guard isOk (isValidJsonElement
  (Json.mkObj [("name", .str "x"), ("status", .str "pass")]))
#guard isOk (isValidJsonElement
  (Json.mkObj [("name", .str "x"), ("status", .str "fail")]))
#guard isOk (isValidJsonElement
  (Json.mkObj [("name", .str "x"), ("status", .str "unknown")]))
#guard isOk (isValidJsonElement
  (Json.mkObj [("name", .str "x"), ("status", .str "implementation_error")]))
#guard isOk (isValidJsonElement
  (Json.mkObj [("name", .str "not-verified"), ("status", .str "not_verified"),
               ("line", .num 4), ("col", .num 42)]))

-- Unknown status rejected.
#guard isErr (isValidJsonElement
  (Json.mkObj [("name", .str "x"), ("status", .str "nope")]))

-- Missing `name` rejected.
#guard isErr (isValidJsonElement (Json.mkObj [("status", .str "pass")]))

-- Missing `status` rejected.
#guard isErr (isValidJsonElement (Json.mkObj [("name", .str "x")]))

-- Non-string `name` rejected.
#guard isErr (isValidJsonElement
  (Json.mkObj [("name", .num 1), ("status", .str "pass")]))

-- `line` without `col` rejected.
#guard isErr (isValidJsonElement
  (Json.mkObj [("name", .str "x"), ("status", .str "pass"),
               ("line", .num 10)]))

-- `col` without `line` rejected.
#guard isErr (isValidJsonElement
  (Json.mkObj [("name", .str "x"), ("status", .str "pass"),
               ("col", .num 4)]))

-- Non-natural `line` rejected.
#guard isErr (isValidJsonElement
  (Json.mkObj [("name", .str "x"), ("status", .str "pass"),
               ("line", .str "oops"), ("col", .num 4)]))

end JsonShape

/-! ## section PipelineJsonShape

    Property 6 — `--pipeline-json` shape, realizing REQ-PBT-006
    (and, via its pre/post-conditions, REQ-OUT-040..REQ-OUT-045,
    REQ-CLI-013, REQ-CLI-022, REQ-CLI-023, REQ-CLI-040).

    The per-output predicate `isValidPipelineJson` is the pure body of
    the property. The fixture matrix `pipelineJsonFixtureMatrix` plays
    the role of `Gen.elements fixtures` — a Plausible property would
    sample from it; the `#eval` below enumerates it deterministically.

    Exact-key enforcement. The property fails on EITHER missing keys OR
    extra keys, at every level: the top-level object, every
    `obligations[i]`, and `summary`. `Std.TreeMap.Raw.keys` returns keys
    in sorted order, so we compare to the sorted expected-key list
    directly. -/
section PipelineJsonShape

/-- The top-level keys the `--pipeline-json` object must have, in any
    order (REQ-OUT-040), plus `warnings`: the annotations and functions
    that are not verified. -/
def pipelineTopKeys : List String :=
  ["laurel", "core", "obligations", "summary", "warnings"]

/-- The four keys each `obligations[i]` must have (REQ-OUT-043). -/
def pipelineObligationKeys : List String :=
  ["label", "status", "smt", "smtResult"]

/-- The integer keys `summary` must have (REQ-OUT-044), plus `errors`
    (obligations nothing checked: an encoding error, a solver crash) and
    `notVerified` (the number of warnings). -/
def pipelineSummaryKeys : List String :=
  ["total", "passed", "failed", "unknown", "errors", "notVerified"]

/-- Legal values for the `obligations[i].status` field (REQ-OUT-043),
    plus `error` for an obligation nothing checked (`--json` spells it
    `implementation_error`, see REQ-PBT-005). -/
def pipelineObligationStatuses : List String :=
  ["pass", "fail", "unknown", "error"]

/-- Legal values for the `obligations[i].smtResult` field
    (REQ-OUT-043), plus `error`. -/
def pipelineSmtResultValues : List String :=
  ["unsat", "sat", "unknown", "error"]

/-- The curated fixture matrix for REQ-PBT-006.

    Chosen small and fast, and picked to cover all three obligation
    statuses at least once across the matrix:
      * `test_arithmetic` — mostly-passing arithmetic fixture; exercises
        the `pass` / `unsat` branch. Also used by the REQ-PBT-002
        determinism driver, which keeps the characterization and
        determinism axes aligned.
      * `test_spec_basic` — a mix of `pass` results with and without
        resolved source positions; further stress on the `pass` branch.
      * `test_assert_fail` — at least one `fail` result; exercises the
        `fail` / `sat` branch of REQ-OUT-043.

    Together they also exercise REQ-OUT-045's "empty `smt` on read
    failure" branch incidentally, since not all obligations need have
    an accessible SMT artifact. -/
def pipelineJsonFixtureMatrix : List String :=
  [ "test_arithmetic"
  , "test_spec_basic"
  , "test_assert_fail"
  ]

/-- Plausible-style generator over the pipeline-JSON fixture matrix.
    Exposed for documentation / future promotion to a true Plausible
    property. -/
def genPipelineJsonFixture : Plausible.Gen String :=
  Plausible.Gen.elements pipelineJsonFixtureMatrix (by decide)

/-- Compare the actual object keys against an expected key set
    (order-insensitive, exact-match). `Std.TreeMap.Raw.keys` returns
    keys in sorted order, so we sort `expected` and compare lists. -/
private def checkExactKeys (context : String) (j : Json) (expected : List String) :
    Except String Unit := do
  let obj ← j.getObj?
  let actualKeys := obj.keys
  let expectedSorted := expected.mergeSort (· ≤ ·)
  if actualKeys != expectedSorted then
    throw s!"{context}: expected keys {expectedSorted}, got {actualKeys}"
  pure ()

/-- Validate one `obligations[i]` element:
      * Exact keys `label`, `status`, `smt`, `smtResult`.
      * `label` is a string.
      * `status ∈ {"pass","fail","unknown","error"}` (REQ-OUT-043).
      * `smt` is a string (may be empty per REQ-OUT-045).
      * `smtResult ∈ {"unsat","sat","unknown","error"}` (REQ-OUT-043). -/
def isValidObligation (j : Json) : Except String Unit := do
  checkExactKeys "obligation" j pipelineObligationKeys
  -- label : String
  let labelJ ← j.getObjVal? "label"
  let _label ← labelJ.getStr?
  -- status : String ∈ {pass,fail,unknown,error}
  let statusJ ← j.getObjVal? "status"
  let status ← statusJ.getStr?
  if !pipelineObligationStatuses.contains status then
    throw s!"obligation status {status} not in {pipelineObligationStatuses}"
  -- smt : String
  let smtJ ← j.getObjVal? "smt"
  let _smt ← smtJ.getStr?
  -- smtResult : String ∈ {unsat,sat,unknown,error}
  let smtResultJ ← j.getObjVal? "smtResult"
  let smtResult ← smtResultJ.getStr?
  if !pipelineSmtResultValues.contains smtResult then
    throw s!"obligation smtResult {smtResult} not in {pipelineSmtResultValues}"

/-- Validate the `summary` sub-object:
      * Exact keys `total`, `passed`, `failed`, `unknown`, `errors`,
        `notVerified`.
      * All values are non-negative integers (REQ-OUT-044).
      * `total = passed + failed + unknown + errors`.
    Returns `(total, notVerified)`, which the caller checks against the
    `obligations` and `warnings` arrays. -/
def isValidSummary (j : Json) : Except String (Nat × Nat) := do
  checkExactKeys "summary" j pipelineSummaryKeys
  let count : String → Except String Nat := fun key => do
    let v ← j.getObjVal? key
    v.getNat?
  let total ← count "total"
  let parts ← ["passed", "failed", "unknown", "errors"].mapM count
  let sum := parts.foldl (· + ·) 0
  if total != sum then
    throw s!"summary: total {total} is not passed + failed + unknown + errors = {sum}"
  return (total, ← count "notVerified")

/-- Validate one `warnings[i]` element: a `message : String`, and `line`
    and `col` either both present (both `Nat`) or both absent. -/
def isValidWarning (j : Json) : Except String Unit := do
  let obj ← j.getObj?
  let hasPos := obj.contains "line" || obj.contains "col"
  checkExactKeys "warning" j (if hasPos then ["message", "line", "col"] else ["message"])
  let _message ← (← j.getObjVal? "message").getStr?
  if hasPos then
    let _line ← (← j.getObjVal? "line").getNat?
    let _col ← (← j.getObjVal? "col").getNat?

/-- The full-output property for REQ-PBT-006. Parses the stdout, enforces
    the exact top-level key set, and validates each sub-structure.

    Checks, in order:
      1. stdout is a JSON object.
      2. Top-level keys are exactly `{laurel, core, obligations, summary,
         warnings}`.
      3. `laurel` is a string (REQ-OUT-041).
      4. `core` is a string (REQ-OUT-042).
      5. `obligations` is an array; every element passes
         `isValidObligation` (REQ-OUT-043).
      6. `summary` passes `isValidSummary` (REQ-OUT-044), and its `total`
         is the number of obligations.
      7. `warnings` is an array; every element passes `isValidWarning`,
         and there are `summary.notVerified` of them. -/
def isValidPipelineJson (stdout : String) : Except String Unit := do
  let j ← Json.parse stdout
  checkExactKeys "top-level" j pipelineTopKeys
  -- laurel : String
  let laurelJ ← j.getObjVal? "laurel"
  let _laurel ← laurelJ.getStr?
  -- core : String
  let coreJ ← j.getObjVal? "core"
  let _core ← coreJ.getStr?
  -- obligations : Array of valid obligation objects
  let obligationsJ ← j.getObjVal? "obligations"
  let obligations ← obligationsJ.getArr?
  for (elt, i) in obligations.toList.zipIdx do
    match isValidObligation elt with
    | .ok () => pure ()
    | .error msg => throw s!"obligations[{i}] invalid: {msg}"
  -- summary
  let summaryJ ← j.getObjVal? "summary"
  let (total, notVerified) ← isValidSummary summaryJ
  if total != obligations.size then
    throw s!"summary: total {total} but {obligations.size} obligations"
  -- warnings : Array of valid warning objects, `notVerified` of them
  let warnings ← (← j.getObjVal? "warnings").getArr?
  for (elt, i) in warnings.toList.zipIdx do
    match isValidWarning elt with
    | .ok () => pure ()
    | .error msg => throw s!"warnings[{i}] invalid: {msg}"
  if warnings.size != notVerified then
    throw s!"summary: notVerified {notVerified} but {warnings.size} warnings"

/-- Helper for the `#eval` below: run the pipeline for one fixture under
    `--pipeline-json` and apply the property. Mirrors `checkFixture`
    from `section JsonShape`. -/
def checkPipelineFixture (paths : TestPaths) (fixtureName : String) : IO Bool := do
  match ← runFixturePipelineJson paths fixtureName with
  | .error reason =>
    IO.eprintln s!"FAIL {fixtureName} (--pipeline-json): {reason}"
    return false
  | .ok stdout =>
    match isValidPipelineJson stdout with
    | .ok () =>
      IO.println s!"PASS {fixtureName} (--pipeline-json)"
      return true
    | .error msg =>
      IO.eprintln s!"FAIL {fixtureName} (--pipeline-json): {msg}\nstdout was:\n{stdout}"
      return false

/- The entry point. Loops over `pipelineJsonFixtureMatrix` and enforces
   the REQ-PBT-006 shape invariants on every fixture's `--pipeline-json`
   output.

   Using `assert!` ensures this `#eval` aborts with a non-zero exit
   status on any failure, which propagates through `lake test`. -/
#eval show IO Unit from do
  let paths ← mkTestPaths
  let mut allOk := true
  for fixture in pipelineJsonFixtureMatrix do
    let ok ← checkPipelineFixture paths fixture
    allOk := allOk && ok
  assert! allOk

/-! Sanity checks on the pure predicate itself — make sure a well-formed
    output passes and every failure mode is caught. These are unit-level
    reinforcements of the property body and run at elab time without
    invoking the binary. Reuses the module-private `isOk` / `isErr`
    helpers defined in `section JsonShape` above. Each rejected object
    differs from a well-formed one in exactly the defect it names. -/

/-- A `summary` object with the given counts, in key order. -/
private def summaryObj (total passed failed unknown errors notVerified : Nat) : Json :=
  Json.mkObj [
    ("total", .num total), ("passed", .num passed), ("failed", .num failed),
    ("unknown", .num unknown), ("errors", .num errors),
    ("notVerified", .num notVerified)]

/-- A `--pipeline-json` object with the given parts; `extra` adds keys. -/
private def pipelineObj (obligations : Array Json) (summary : Json)
    (warnings : Array Json := #[]) (extra : List (String × Json) := []) : Json :=
  Json.mkObj ([
    ("laurel", .str "L"),
    ("core", .str "C"),
    ("obligations", .arr obligations),
    ("summary", summary),
    ("warnings", .arr warnings)] ++ extra)

/-- An obligation with the given status and SMT result. -/
private def obligation (label status smtResult : String) : Json :=
  Json.mkObj [
    ("label", .str label), ("status", .str status),
    ("smt", .str ""), ("smtResult", .str smtResult)]

/-- A warning, with or without a position. -/
private def warning (message : String) (pos : Option (Nat × Nat) := none) : Json :=
  Json.mkObj ([("message", .str message)] ++
    match pos with
    | some (line, col) => [("line", .num line), ("col", .num col)]
    | none => [])

-- Well-formed: minimal (no obligations, no warnings).
#guard isOk (isValidPipelineJson (pipelineObj #[] (summaryObj 0 0 0 0 0 0)).compress)

-- Well-formed: one obligation of each status, and a warning with and
-- one without a position.
#guard isOk (isValidPipelineJson (pipelineObj
  #[obligation "p" "pass" "unsat", obligation "f" "fail" "sat",
    obligation "u" "unknown" "unknown", obligation "e" "error" "error"]
  (summaryObj 4 1 1 1 1 2)
  #[warning "ignored" (some (4, 42)), warning "not verified"]).compress)

-- Reject: missing `laurel`.
#guard isErr (isValidPipelineJson
  (Json.mkObj [
    ("core", .str "C"), ("obligations", .arr #[]),
    ("summary", summaryObj 0 0 0 0 0 0), ("warnings", .arr #[])]).compress)

-- Reject: missing `warnings`.
#guard isErr (isValidPipelineJson
  (Json.mkObj [
    ("laurel", .str "L"), ("core", .str "C"), ("obligations", .arr #[]),
    ("summary", summaryObj 0 0 0 0 0 0)]).compress)

-- Reject: extra top-level key.
#guard isErr (isValidPipelineJson
  (pipelineObj #[] (summaryObj 0 0 0 0 0 0) (extra := [("extra", .str "nope")])).compress)

-- Reject: non-string `laurel`.
#guard isErr (isValidPipelineJson
  (Json.mkObj [
    ("laurel", .num 1), ("core", .str "C"), ("obligations", .arr #[]),
    ("summary", summaryObj 0 0 0 0 0 0), ("warnings", .arr #[])]).compress)

-- Reject: obligation missing `smt`.
#guard isErr (isValidPipelineJson (pipelineObj
  #[Json.mkObj [("label", .str "x"), ("status", .str "pass"), ("smtResult", .str "unsat")]]
  (summaryObj 1 1 0 0 0 0)).compress)

-- Reject: obligation with extra key.
#guard isErr (isValidPipelineJson (pipelineObj
  #[Json.mkObj [
    ("label", .str "x"), ("status", .str "pass"), ("smt", .str ""),
    ("smtResult", .str "unsat"), ("extra", .num 1)]]
  (summaryObj 1 1 0 0 0 0)).compress)

-- Reject: obligation with an unknown status (`--json`'s spelling of an
-- error is not `--pipeline-json`'s).
#guard isErr (isValidPipelineJson (pipelineObj
  #[obligation "x" "implementation_error" "error"] (summaryObj 1 0 0 0 1 0)).compress)

-- Reject: obligation with an unknown smtResult.
#guard isErr (isValidPipelineJson (pipelineObj
  #[obligation "x" "pass" "bogus"] (summaryObj 1 1 0 0 0 0)).compress)

-- Reject: summary missing `errors`.
#guard isErr (isValidPipelineJson (pipelineObj #[]
  (Json.mkObj [
    ("total", .num 0), ("passed", .num 0), ("failed", .num 0),
    ("unknown", .num 0), ("notVerified", .num 0)])).compress)

-- Reject: summary with extra key.
#guard isErr (isValidPipelineJson (pipelineObj #[]
  (Json.mkObj [
    ("total", .num 0), ("passed", .num 0), ("failed", .num 0),
    ("unknown", .num 0), ("errors", .num 0), ("notVerified", .num 0),
    ("extra", .num 0)])).compress)

-- Reject: summary with non-integer value.
#guard isErr (isValidPipelineJson (pipelineObj #[]
  (Json.mkObj [
    ("total", .str "0"), ("passed", .num 0), ("failed", .num 0),
    ("unknown", .num 0), ("errors", .num 0), ("notVerified", .num 0)])).compress)

-- Reject: total is not the sum of the outcome counts.
#guard isErr (isValidPipelineJson (pipelineObj
  #[obligation "p" "pass" "unsat"] (summaryObj 1 0 0 0 0 0)).compress)

-- Reject: total is not the number of obligations.
#guard isErr (isValidPipelineJson (pipelineObj
  #[obligation "p" "pass" "unsat"] (summaryObj 2 2 0 0 0 0)).compress)

-- Reject: `notVerified` is not the number of warnings.
#guard isErr (isValidPipelineJson (pipelineObj #[]
  (summaryObj 0 0 0 0 0 0) #[warning "ignored"]).compress)

-- Reject: warning without a message.
#guard isErr (isValidPipelineJson (pipelineObj #[]
  (summaryObj 0 0 0 0 0 1) #[Json.mkObj [("line", .num 1), ("col", .num 1)]]).compress)

-- Reject: warning with `line` but no `col`.
#guard isErr (isValidPipelineJson (pipelineObj #[]
  (summaryObj 0 0 0 0 0 1)
  #[Json.mkObj [("message", .str "m"), ("line", .num 1)]]).compress)

-- Reject: `obligations` is not an array.
#guard isErr (isValidPipelineJson
  (Json.mkObj [
    ("laurel", .str "L"), ("core", .str "C"), ("obligations", .str "not an array"),
    ("summary", summaryObj 0 0 0 0 0 0), ("warnings", .arr #[])]).compress)

-- Reject: stdout is not an object (e.g. bare array from `--json` mode).
#guard isErr (isValidPipelineJson "[]")

end PipelineJsonShape

end Strata.Solidity.Test.JsonOutput
