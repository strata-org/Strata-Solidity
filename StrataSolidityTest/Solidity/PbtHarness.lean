/-
  Shared Plausible property-based testing harness for Strata Solidity tests.

  Exposes:

  * `Strata.Solidity.Test.Pbt.pbtConfig` — a `Plausible.Configuration` with a
    fixed random seed and a modest sample count, used by every
    characterization PBT module under `StrataSolidityTest/Solidity/`. Fixing
    the seed keeps `lake test` runs reproducible and lets a counter-example
    be replayed locally by anyone who sees a CI failure.

  * Helper generators used by parser / serializer round-trip tests:
    `genIdentifier`, `genIntLiteral`, `genSpecKeyword`, plus the raw
    `specKeywords` list for deterministic iteration.

  Realizes: REQ-TEST-001, REQ-TEST-002, REQ-TEST-003; shared foundation for
  REQ-PBT-001..REQ-PBT-008.

  See `.kiro/specs/strata-solidity-baseline/{requirements,design}.md` §13 for
  the characterization PBT specification that this harness supports.

  REQ-PBT-003 (Golden-test stability) is realized by the existing golden
  harness `run_sol_analyze_laurel.sh` rather than by a Lean module. See
  `PBT_EVIDENCE.md` in this directory for the line-by-line mapping from
  REQ-PBT-003, REQ-TEST-011, REQ-TEST-012, and REQ-TEST-014 to the specific
  shell lines that realize them.

  Note on naming: `requirements.md` §13 and `tasks.md` §2.1 refer to a
  "`Plausible.Testable.Config`". The actual type exported by the upstream
  Plausible package is `Plausible.Configuration`; we bind it here as
  `pbtConfig` and document the equivalence in-line to avoid ambiguity for
  downstream consumers.
-/
import Plausible

namespace Strata.Solidity.Test.Pbt

open Plausible

/-! ## Shared configuration -/

/-- Shared Plausible configuration for every characterization PBT module.

    * `randomSeed := some 42` pins the RNG seed so runs are reproducible and
      counter-examples replay locally.
    * `numInst := 50` is a modest sample count — enough to catch the
      easily-generated round-trip failures the baseline cares about without
      noticeably slowing down `lake test`.
    * `quiet := true` silences passing tests; only counter-examples surface. -/
def pbtConfig : Plausible.Configuration where
  randomSeed := some 42
  numInst := 50
  quiet := true

/-! ## Spec keywords (REQ-SPEC-004) -/

/-- The five spec keywords recognized by
    `Strata.Solidity.parseStrataAnnotations` (REQ-SPEC-004). Exposed as a
    plain list so that round-trip tests can iterate over it deterministically
    in addition to sampling via `genSpecKeyword`. -/
def specKeywords : List String :=
  ["requires", "ensures", "invariant", "modifies", "loop-invariant"]

/-- Pick one of the five spec keywords uniformly at random. -/
def genSpecKeyword : Gen String :=
  Gen.elements specKeywords (by decide)

/-! ## Identifier generator (REQ-SPEC-020) -/

/-- Characters allowed as the first character of a generated identifier:
    ASCII letters and underscore. This matches the tokens that
    `SpecParser.tokenize` classifies as word tokens (REQ-SPEC-020) and avoids
    operator characters (`+`, `-`, `*`, `/`, `%`, `=`, `<`, `>`, `&`, `|`,
    `.`, `,`, `(`, `)`, `[`, `]`, `:`, `!`) which would otherwise split the
    token. -/
private def identifierHeadChars : List Char :=
  ['a','b','c','d','e','f','g','h','i','j','k','l','m',
   'n','o','p','q','r','s','t','u','v','w','x','y','z',
   'A','B','C','D','E','F','G','H','I','J','K','L','M',
   'N','O','P','Q','R','S','T','U','V','W','X','Y','Z',
   '_']

/-- Characters allowed after the first character: everything in
    `identifierHeadChars`, plus the digits `0`-`9`. -/
private def identifierTailChars : List Char :=
  identifierHeadChars ++ ['0','1','2','3','4','5','6','7','8','9']

/-- Generate a syntactically valid Solidity-like identifier: starts with a
    letter or underscore, followed by up to seven letter/digit/underscore
    characters. The length cap keeps generated annotations small enough to
    be readable when they appear in a counter-example report. -/
def genIdentifier : Gen String := do
  let head ← Gen.elements identifierHeadChars (by decide)
  let tailLen ← Gen.choose Nat 0 7 (by decide)
  let mut s := String.ofList [head]
  for _ in [0:tailLen.val] do
    let c ← Gen.elements identifierTailChars (by decide)
    s := s.push c
  return s

/-! ## Integer-literal generator (REQ-SPEC-020) -/

/-- Integer literals accepted by `SpecParser`, including scientific notation
    like `1e24` (REQ-SPEC-020). About one in three draws produces a
    scientific-notation form; the remainder are plain decimal numerals in
    `[0, 10^9]`. Both shapes are round-trip-decoded by
    `SpecParser.parseSciNotation`. -/
def genIntLiteral : Gen String := do
  let mode ← Gen.choose Nat 0 2 (by decide)
  if mode.val = 0 then
    -- Scientific notation: `1e24`, `5e3`, …
    let mantissa ← Gen.choose Nat 1 9 (by decide)
    let exponent ← Gen.choose Nat 0 30 (by decide)
    return s!"{mantissa.val}e{exponent.val}"
  else
    -- Plain decimal.
    let n ← Gen.choose Nat 0 1000000000 (by decide)
    return toString n.val

end Strata.Solidity.Test.Pbt
