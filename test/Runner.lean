/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

/-!
# Typed test runner — Group C scaffold

Replaces (eventually) `test/run_tests.sh` (the bash golden-test runner) with
a typed Lean program. See `.kiro/specs/pipeline-language-rationalization/`
(REQ-HARN-001..REQ-HARN-040) for full requirements.

## Status: SCAFFOLD

Not yet wired into the build. Currently just demonstrates the pattern.
The existing `test/run_tests.sh` continues to be the canonical runner
until this skeleton is fleshed out and gated behind a parity check.

## Design principle: invoke the binary, not a shell wrapper

The point of Group C is to remove the bash boundary. Therefore this runner
shells out to the *binaries* that do the real work — `python3 -m src.solast`
and `.lake/build/bin/strataSolidity` — not to `Tools/Solidity/scripts/strata-verify.sh`.
The shell wrapper itself becomes one of the ≤30-LOC forwarders described in
REQ-WRAP-001 (it stays for muscle-memory and CI scripts that already use it).

`StrataSolidityTest/Solidity/JsonOutputTest.lean` is the existing reference
for direct binary invocation in Lean — same shape, same `IO.Process.output`
pattern.

After Group B lands (Lean front-end), the `solast.py` step disappears and
the runner becomes a single subprocess call to the verifier on the `.sol`
input directly.

## Behavior to preserve

`test/run_tests.sh`'s contract:

  1. Verify the Strata submodule is initialized (the `scripts/check-strata.sh`
     check; trivially reimplementable as a Lean `pathExists` check on
     `Strata/lakefile.toml`).
  2. Discover fixtures: every `test/examples/*.sol`.
  3. For each fixture:
     a. Run `python3 -m src.solast sol_to_strata --dialect <dialect> <sol> <ion>`
        to convert `.sol` to Ion (until Group B replaces this).
     b. Run `.lake/build/bin/strataSolidity <ion>` and capture stdout.
     c. `grep` the relevant lines, diff against `test/expected/<basename>.expected`.
  4. Report `<n> passed, <m> failed, <k> skipped, <g> generated`.
  5. Run the exit-code contract sub-stage (REQ-PBT-007) — three additional
     contracts checked for specific exit codes.

This Lean runner must produce equivalent output and exit code.

## Migration plan

  1. Implement `discover : IO (Array System.FilePath)` — list `*.sol` under
     `test/examples/`.
  2. Implement `generateIon : System.FilePath → System.FilePath → IO Unit` —
     subprocess to `python3 -m src.solast`, mirroring `JsonOutputTest.generateIon`.
  3. Implement `runStrata : System.FilePath → IO String` — subprocess to
     `.lake/build/bin/strataSolidity`, capturing stdout (with the same
     line-filter the bash runner applies).
  4. Implement `diff : String → System.FilePath → IO Bool` — compare actual
     vs `test/expected/<basename>.expected`.
  5. Aggregate, format, exit. Match the bash runner's output verbatim or
     accept a `--legacy` flag for parity during transition.
  6. Wire into `lakefile.lean` as `script run-tests` (mirror the existing
     `pbt-determinism` pattern).
  7. Reduce `test/run_tests.sh` to a ≤30-LOC forwarder that invokes
     `lake run run-tests` (REQ-WRAP-001). After Group B lands, drop the
     `generateIon` step.

## Why Lean and not Python

Both work. Lean wins on:

- Single-language repo for the verification pipeline (one of the spec's
  guiding principles).
- Reuses `IO.Process` and `System.FilePath` from Lean stdlib; no new
  dependencies.
- Zero runtime overhead: precompiled into the same lake build.

Python loses on:

- Adds a Python boundary the spec is trying to eliminate.
- Requires venv management to run tests.
-/

namespace StrataSolidityTest.Runner

structure TestResult where
  fixture : System.FilePath
  passed : Bool
  details : String
deriving Inhabited

/-- TODO: discover all `test/examples/*.sol` files. -/
def discover : IO (Array System.FilePath) := do
  -- Stub: real implementation should walk `test/examples/` and return
  -- entries matching `*.sol`, deterministically sorted.
  pure #[]

/-- TODO: convert `<fixture>.sol` to Ion via the `solast.py` subprocess.
    Until Group B (Lean front-end) lands, this remains the bridge from
    `.sol` to the binary's input format. -/
def generateIon (_solPath _ionPath : System.FilePath) : IO Unit := do
  -- Stub: real implementation runs `python3 -m src.solast sol_to_strata`
  -- with PYTHONPATH set to Strata/Tools/Python, mirroring the existing
  -- StrataSolidityTest/Solidity/JsonOutputTest.lean:generateIon helper.
  pure ()

/-- TODO: invoke the `strataSolidity` binary on `<fixture>.solidity.st.ion`
    and return its stdout. -/
def runStrata (_ionPath : System.FilePath) : IO String := do
  -- Stub: real implementation runs `.lake/build/bin/strataSolidity <ion>`
  -- via `IO.Process.output`, captures stdout.
  pure ""

/-- TODO: run a single fixture end-to-end and diff against expected. -/
def runOne (fixture : System.FilePath) : IO TestResult := do
  -- Stub: real implementation should:
  --   1. generateIon fixture <tmp>/<basename>.solidity.st.ion
  --   2. let stdout ← runStrata <tmp>/<basename>.solidity.st.ion
  --   3. read `test/expected/<basename>.expected`
  --   4. diff; return TestResult
  pure { fixture, passed := false, details := "scaffold not yet implemented" }

/-- TODO: orchestrate. Mirror the bash runner's output and exit code. -/
def main (_args : List String) : IO UInt32 := do
  let fixtures ← discover
  let mut nPass := 0
  let mut nFail := 0
  for f in fixtures do
    let r ← runOne f
    if r.passed then nPass := nPass + 1 else nFail := nFail + 1
    IO.println s!"{if r.passed then \"✅\" else \"❌\"} {f}"
  IO.println s!"\n{nPass} passed, {nFail} failed, 0 skipped, 0 generated"
  return if nFail > 0 then 1 else 0

end StrataSolidityTest.Runner

/-- Lake script entry point: `lake run run-tests`.
    Wire this into lakefile.lean as a `script` target once implemented. -/
def main (args : List String) : IO UInt32 := StrataSolidityTest.Runner.main args
