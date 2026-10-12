import Lake

open System Lake DSL

package StrataSolidity where
  testDriver := "StrataSolidityTest"
  version := v!"0.1.0"

require Strata from "Strata"

@[default_target] lean_lib StrataSolidity

@[default_target] lean_exe strataSolidity where root := `StrataSolidityMain

lean_lib StrataSolidityTest where
  globs := #[`StrataSolidityTest.+]
  -- `JsonOutputTest` runs the binary: build it first, and run the tests
  -- again whenever it changes (otherwise Lake replays their cached result).
  needs := #[strataSolidity]

/--
Group A step 2: print a structural summary of the Lean-built Solidity DDM
dialect (`StrataSolidity/SolidityDialectLean.lean`). One line per
declaration, sorted by name, deterministic.

Usage:
  lake exe gen-dialect-summary
  lake exe gen-dialect-summary > snapshots/lean-dialect.txt

Diff two versions of the Lean dialect across a PR with:
  diff -u snapshots/lean-dialect.txt <(lake exe gen-dialect-summary)

See `StrataSolidity/DialectSummary.lean` for full rationale.
-/
lean_exe «gen-dialect-summary» where root := `StrataSolidity.DialectSummary

/--
Property 2: Pipeline determinism (REQ-PBT-002).

Runs `StrataSolidityTest/Solidity/run_pbt_determinism.sh`, which invokes
`strata-verify.sh <fixture.sol> --pipeline-json` twice against a small,
representative Solidity fixture and checks that the five structural
determinism invariants — `laurel`, `core`, `obligations[*].label`,
`obligations[*].status`, and `summary` — are byte-equal across runs.

Exits non-zero on any difference in those five fields.

Validates: REQ-PBT-002, REQ-PIPE-001..REQ-PIPE-005, REQ-OUT-040..REQ-OUT-045.

Usage:
  lake run pbt-determinism [-- <path/to/fixture.sol>]

If no fixture is passed, the driver defaults to
`StrataSolidityTest/Solidity/tests/test_arithmetic.sol`.
-/
script «pbt-determinism» args do
  let ws ← getWorkspace
  let driver := ws.dir / "StrataSolidityTest" / "Solidity" / "run_pbt_determinism.sh"
  if !(← driver.pathExists) then
    IO.eprintln s!"Error: PBT determinism driver not found at {driver}"
    return 2
  let proc ← IO.Process.spawn {
    cmd := driver.toString
    args := args.toArray
    cwd := ws.dir
  }
  let exit ← proc.wait
  return exit
