/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

import StrataSolidity.SolidityDialect

/-!
# `lake exe gen-dialect-summary` — print a structural snapshot of the Lean dialect

Group A step 2 of `.kiro/specs/pipeline-language-rationalization/`.
Produces a deterministic, human-readable summary of the canonical `Solidity` dialect so
contributors can:

  * inspect what the Lean dialect declares without reading the Lean source,
  * diff two versions of the Lean dialect across PRs (the output is sorted
    by name for stable diffs),
  * cross-check against `Tools/Solidity/src/base_dialect.py` line-by-line.

Step 3 (in a follow-up PR) adds a compile-time structural parity check that
compares this same shape against the Ion-loaded canonical dialect, failing
`lake test` on drift.

## Why a summary, not a full Ion regeneration

A round-trip Lean → Ion serializer would be the strongest possible drift
gate (byte-equality with the checked-in `Solidity.dialect.st.ion`), but
Strata's Lean side has no public `Dialect.toIon` encoder. Writing one from
scratch is multi-day work and adds a maintenance surface.

The structural summary catches the same drift modes — added / removed /
renamed op or arg — without requiring the Ion encoder. Steps 4+ of the
migration (switching `SolidityDialect.lean` off `#load_dialect` onto the
Lean source) replace the canonical-Ion path entirely, at which point the
byte-equality check becomes irrelevant anyway.

## Output format

One line per declaration, sorted alphabetically by name:

```
syncat node
syncat opt_node
…
op missing_node : SolidityLean.opt_node
op some_node    : SolidityLean.opt_node (x)
op SourceUnit   : Init.Command (nodes)
op ContractDefinition : SolidityLean.node (name, contractKind, nodes, documentation, baseContracts)
…
```

The format is intentionally line-oriented and stable so that a `diff -u` of
two runs is the natural way to see what changed.
-/

open Strata

private def declSummary (decl : Decl) : Option String :=
  match decl with
  | .syncat s => some s!"syncat {s.name}"
  | .op o     =>
    let argList := String.intercalate ", " (o.argDecls.toArray.map (·.ident)).toList
    some s!"op {o.name} : {o.category} ({argList})"
  | .type t   => some s!"type {t.name}"
  | _         => none

def main : IO Unit := do
  let d := Strata.Solidity.Solidity
  let lines := d.declarations.filterMap declSummary
  let sorted := lines.qsort (· < ·)
  IO.println s!"# Solidity dialect — structural summary"
  IO.println s!"# Generated from StrataSolidity/SolidityDialect.lean"
  IO.println s!"# {d.declarations.size} total declarations"
  IO.println ""
  for line in sorted do
    IO.println line
