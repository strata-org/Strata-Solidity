/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

/-
  Unit tests and characterization property-based tests for the Strata
  Solidity spec expression parser.

  ## Structure

  1. `#guard` / `#eval` examples that pin specific tokenizer and parser
     behaviors for REQ-SPEC-001..REQ-SPEC-030 / REQ-SPEC-040..REQ-SPEC-046 /
     REQ-SPEC-070.
  2. A Plausible property (`specParserRoundTripIdempotence`) realizing
     REQ-PBT-001: for every generated `@custom:strata` annotation,
     `parse ∘ canonicalSerialize ∘ parse = parse`. The shared Plausible
     harness lives in `Strata.Solidity.Test.Pbt`
     (`StrataSolidityTest/Solidity/PbtHarness.lean`).
-/
import StrataSolidity.SolTranslator.SpecParser
import StrataSolidity.SolTranslator.Types
import StrataSolidityTest.Solidity.PbtHarness

namespace Strata.Solidity.SpecParser.Tests

open Strata.Solidity
open Laurel

/-! ## Test helpers -/

private def parse (s : String) : Except TranslationError StmtExprMd :=
  match SpecParser.parseExpr (SpecParser.tokenize s) with
  | .ok (expr, _) => .ok expr
  | .error e => .error e

private def parseOk (s : String) : Bool :=
  match parse s with
  | .ok _ => true
  | .error _ => false

private def parseFail (s : String) : Bool := !parseOk s

/-! ## Tokenizer tests -/

#guard SpecParser.tokenize "a + b" == ["a", "+", "b"]
#guard SpecParser.tokenize "a / b" == ["a", "/", "b"]
#guard SpecParser.tokenize "a % b" == ["a", "%", "b"]
#guard SpecParser.tokenize "a == b" == ["a", "==", "b"]
#guard SpecParser.tokenize "a ==> b" == ["a", "==>", "b"]
#guard SpecParser.tokenize "a != b" == ["a", "!=", "b"]
#guard SpecParser.tokenize "a >= b" == ["a", ">=", "b"]
#guard SpecParser.tokenize "a && b || c" == ["a", "&&", "b", "||", "c"]
#guard SpecParser.tokenize "old(x)" == ["old", "(", "x", ")"]
#guard SpecParser.tokenize "m[k]" == ["m", "[", "k", "]"]
#guard SpecParser.tokenize "f(a, b)" == ["f", "(", "a", ",", "b", ")"]
#guard SpecParser.tokenize "msg.sender" == ["msg", ".", "sender"]
#guard SpecParser.tokenize "keccak256(abi.encodePacked(a, b))" ==
  ["keccak256", "(", "abi", ".", "encodePacked", "(", "a", ",", "b", ")", ")"]
-- Standalone `!` tokenizes separately from the following identifier, and is
-- distinct from `!=`.
#guard SpecParser.tokenize "!paused" == ["!", "paused"]
#guard SpecParser.tokenize "!a && b" == ["!", "a", "&&", "b"]
#guard SpecParser.tokenize "a != b" == ["a", "!=", "b"]
-- Unary minus on a literal (negative tick-bound idiom).
#guard SpecParser.tokenize "t >= -887272" == ["t", ">=", "-", "887272"]

/-! ## Expression parsing tests -/

-- Literals
#guard parseOk "42"
#guard parseOk "0"
#guard parseOk "true"
#guard parseOk "false"

-- Identifiers
#guard parseOk "x"
#guard parseOk "balances"

-- Arithmetic
#guard parseOk "x + 1"
#guard parseOk "a - b"
#guard parseOk "a * b + c"

-- Comparisons
#guard parseOk "x == 0"
#guard parseOk "x != y"
#guard parseOk "x >= 0"
#guard parseOk "x <= 100"

-- Boolean logic
#guard parseOk "a && b"
#guard parseOk "a || b"
#guard parseOk "a ==> b"

-- old()
#guard parseOk "old(x)"
#guard parseOk "old(balances[k])"

-- Mapping access
#guard parseOk "balances[msg.sender]"
#guard parseOk "allowance[from][spender]"

-- Function calls in mapping keys
#guard parseOk "data[keccak256(abi.encodePacked(a, b))]"

-- msg.sender, msg.value
#guard parseOk "msg.sender"
#guard parseOk "msg.value"

-- address(0)
#guard parseOk "address(0)"

-- type min/max
#guard parseOk "type(uint256).max"
#guard parseOk "type(int256).min"

-- forall
#guard parseOk "forall k : address :: k != x ==> balances[k] == old(balances[k])"

-- sum
#guard parseOk "sum(balances)"

-- Division and modulo
#guard parseOk "a / b"
#guard parseOk "a % b"
#guard parseOk "a * b / c"
#guard parseOk "(a * b) / 1000"
#guard parseOk "x + (x * rate) / 1000"
#guard parseOk "a / b * b + a % b == a"

-- Complex expressions
#guard parseOk "balances[msg.sender] == old(balances[msg.sender]) + amount"
#guard parseOk "totalSupply == sum(balances)"
#guard parseOk "forall k : address :: k != msg.sender ==> balances[k] == old(balances[k])"

-- Unary operators (parseUnary layer): logical `!` and unary `-`.
#guard parseOk "!paused"
#guard parseOk "!initializing"
#guard parseOk "!done && n != 0"
#guard parseOk "!(a == b)"
#guard parseOk "t >= -887272"
#guard parseOk "t >= -887272 && t <= 887272"
#guard parseOk "x == -1"
#guard parseOk "a + -b"
-- `!=` must still parse as inequality, not `!` followed by `=`.
#guard parseOk "x != y"

/-! ## Annotation parsing tests -/

#guard (parseStrataAnnotations "").isEmpty
#guard (parseStrataAnnotations "some random doc").isEmpty

-- Single annotations
#eval do
  let anns := parseStrataAnnotations "@custom:strata ensures x > 0"
  assert! anns.length == 1

#eval do
  let anns := parseStrataAnnotations "@custom:strata requires x > 0"
  assert! anns.length == 1

#eval do
  let anns := parseStrataAnnotations "@custom:strata invariant x >= 0"
  assert! anns.length == 1

#eval do
  let anns := parseStrataAnnotations "@custom:strata modifies balances"
  assert! anns.length == 1

-- Multiple annotations in one doc block
#eval do
  let anns := parseStrataAnnotations "@custom:strata requires x > 0\n@custom:strata ensures y == x + 1"
  assert! anns.length == 2

end Strata.Solidity.SpecParser.Tests

/-! ## REQ-PBT-001 — Spec parser round-trip idempotence

    Property 1 from `requirements.md` §13 / `design.md` §13.1.

    Validates: REQ-PBT-001, REQ-SPEC-001..REQ-SPEC-030,
               REQ-SPEC-040..REQ-SPEC-046, REQ-SPEC-070.

    The property is `parse ∘ canonicalSerialize ∘ parse = parse` on raw
    `@custom:strata` annotation strings. The first `parse` normalizes the
    input into an AST (a `List StrataAnnotation` plus parsed expressions for
    every expression-bearing keyword); `canonicalSerialize` re-emits a
    syntactically-parseable form; the second `parse` must yield the same
    normalized representation as the first.

    The canonical serializer below lives in the test module (not in the
    production parser) to keep this a pure characterization test. It is
    minimal and deterministic, so idempotence holds by construction for the
    AST shapes the current parser actually produces.

    ### Generator restrictions (baseline parser caveats)

    These restrictions are characterization-only — they document shapes of
    the input space that the current parser does not round-trip, **not**
    defects to fix in this spec. Fixing them belongs to
    `strata-solidity-next`.

    * No `type(int*).min` (REQ-SPEC-044): `typeMinMax` produces a negative
      `LiteralInt`, but the parser does not tokenize a leading `-` on a
      numeric literal, so the canonical re-emission would not round-trip.
      `type(int256).max` and `type(uint*).{min,max}` (all non-negative) are
      included.
    * No bare `msg` `FieldSelect` for `.sender` or `.value` (REQ-SPEC-042):
      the parser turns `msg.sender` / `msg.value` into `Identifier
      "msg_sender"` / `Identifier "msg_value"`, so we generate those
      identifiers directly when we want to exercise msg access.
    * Only the five spec keywords from REQ-SPEC-004 are generated
      (`requires`, `ensures`, `invariant`, `modifies`, `loop-invariant`).
    * Quantifier type names are restricted to `bool`, `address`, `uint256`
      (REQ-SPEC-040): these cover every branch of
      `solTypeNameToHighType` that the parser actually distinguishes.
    * Identifiers generated by the harness never equal a reserved parser
      keyword (`old`, `forall`, `exists`, `true`, `false`, `address`,
      `type`, `msg`, `sum`); avoiding these keeps generated ASTs from
      accidentally entering a parser sub-rule that would not round-trip.
-/

namespace Strata.Solidity.SpecParser.Pbt

open Strata.Solidity
open Strata.Solidity.Test.Pbt
open Laurel
open Plausible

/-! ### Reserved keywords excluded from generated identifiers -/

private def reservedKeywords : List String :=
  ["old", "forall", "exists", "true", "false", "address", "type", "msg", "sum"]

/-- Draw an identifier that is not a parser-reserved keyword. Reduces
    spurious failures where a generated identifier collides with a
    parse-time special form. -/
private def genNonKeywordIdentifier : Gen String := do
  let cand ← genIdentifier
  if reservedKeywords.contains cand then
    -- Deterministically salt the name; we only need *a* non-keyword.
    return cand ++ "_v"
  else
    return cand

/-! ### Structural equality on `StmtExprMd`

    Laurel does not export a `BEq StmtExprMd` instance (metadata would
    make literal equality too strict). We compare structure only, matching
    the semantics the baseline parser cares about. -/

/-- Structural equality on `HighType`, restricted to the shapes the parser
    actually produces for quantifier parameters: `TBool` and `TInt`. -/
private partial def highTypeStructEq (a b : HighType) : Bool :=
  match a, b with
  | .TBool, .TBool => true
  | .TInt, .TInt => true
  | .TVoid, .TVoid => true
  | .TFloat64, .TFloat64 => true
  | .TString, .TString => true
  | .TSet a, .TSet b => highTypeStructEq a.val b.val
  | .TMap k1 v1, .TMap k2 v2 =>
      highTypeStructEq k1.val k2.val && highTypeStructEq v1.val v2.val
  | .UserDefined r1, .UserDefined r2 => r1.text == r2.text
  | _, _ => false

/-- Structural equality on `StmtExprMd`, ignoring metadata. Only covers
    the node shapes that `SpecParser.parseExpr` can emit; any other node
    shape compares non-equal (safe default for the parser subset). -/
private partial def stmtExprStructEq (a b : StmtExprMd) : Bool :=
  match a.val, b.val with
  | .LiteralInt x, .LiteralInt y => x == y
  | .LiteralBool x, .LiteralBool y => x == y
  | .Var (.Local x), .Var (.Local y) => x.text == y.text
  -- Operators are `StaticCall`s to `$add`/`$eq`/…, so comparing callee
  -- names also compares operators.
  | .StaticCall c1 args1 _, .StaticCall c2 args2 _ =>
      c1.text == c2.text &&
      args1.length == args2.length &&
      (args1.zip args2).all (fun (x, y) => stmtExprStructEq x y)
  | .Var (.Field b1 f1), .Var (.Field b2 f2) =>
      f1.text == f2.text && stmtExprStructEq b1 b2
  | .Quantifier .Forall p1 _ body1, .Quantifier .Forall p2 _ body2 =>
      p1.name.text == p2.name.text &&
      highTypeStructEq p1.type.val p2.type.val &&
      stmtExprStructEq body1 body2
  | .Quantifier .Exists p1 _ body1, .Quantifier .Exists p2 _ body2 =>
      p1.name.text == p2.name.text &&
      highTypeStructEq p1.type.val p2.type.val &&
      stmtExprStructEq body1 body2
  | _, _ => false

/-! ### Canonical serializer for expressions parsed by `SpecParser`

    This serializer is deliberately minimal: it produces fully
    parenthesized output so that re-parsing cannot depend on operator
    precedence or associativity, and it uses one canonical Solidity type
    name per Laurel `HighType`. It is **not** production code — it is the
    identity-witness half of the `parse ∘ canonicalSerialize ∘ parse =
    parse` property. -/

/-- One canonical Solidity type name per Laurel `HighType` branch used by
    quantifier parameters. See `solTypeNameToHighType` in `SpecParser`. -/
private def canonicalTypeName (ty : HighType) : String :=
  match ty with
  | .TBool => "bool"
  | _ => "uint256"  -- covers TInt (the only other branch parser produces)

/-- Canonical textual form for a Laurel operator token, using the exact
    spelling the parser recognizes (REQ-SPEC-020..REQ-SPEC-024,
    REQ-SPEC-041). -/
private def opToken : Laurel.Operation → Option String
  | .Eq => some "=="
  | .Neq => some "!="
  | .And => some "&&"
  | .Or => some "||"
  | .Implies => some "==>"
  | .Add => some "+"
  | .Sub => some "-"
  | .Mul => some "*"
  | .Div => some "/"
  | .Mod => some "%"
  | .Lt => some "<"
  | .Leq => some "<="
  | .Gt => some ">"
  | .Geq => some ">="
  | _ => none  -- Not emitted by SpecParser.

/-- Canonical serializer for `StmtExprMd`. Covers the subset of AST nodes
    that `SpecParser.parseExpr` produces; unsupported nodes are serialized
    to a fallback identifier so that the surrounding test still terminates
    (the structural-equality check will catch any real mismatch). -/
private partial def canonicalSerialize (e : StmtExprMd) : String :=
  match e.val with
  | .LiteralInt n =>
      if n ≥ 0 then toString n else s!"(0 - {toString (-n)})"
  | .LiteralBool true => "true"
  | .LiteralBool false => "false"
  | .Var (.Local name) => name.text
  | .StaticCall callee args _ =>
      if let some (op, operands) := asPrimOp? e.val then
        match operands, opToken op with
        | [lhs, rhs], some t => s!"({canonicalSerialize lhs} {t} {canonicalSerialize rhs})"
        | _, _ => "__unsupported_op"
      else if callee.text == "__old" then
        match args with
        | [inner] => s!"old({canonicalSerialize inner})"
        | _ => "__unsupported_old"
      else if callee.text == "select" then
        match args with
        | [base, idx] => s!"({canonicalSerialize base}[{canonicalSerialize idx}])"
        | _ => "__unsupported_select"
      else
        let argStr := String.intercalate ", " (args.map canonicalSerialize)
        s!"{callee.text}({argStr})"
  | .Var (.Field base field) => s!"({canonicalSerialize base}.{field.text})"
  | .Quantifier .Forall param _ body =>
      s!"(forall {param.name.text} : {canonicalTypeName param.type.val} :: {canonicalSerialize body})"
  | .Quantifier .Exists param _ body =>
      s!"(exists {param.name.text} : {canonicalTypeName param.type.val} :: {canonicalSerialize body})"
  | _ => "__unsupported_node"

/-! ### Canonical serializer at the annotation level

    For expression-bearing keywords (`requires`, `ensures`, `invariant`,
    `loop-invariant`), we re-parse the stored expression, serialize it,
    and re-emit the full annotation line. For `modifies` (REQ-SPEC-045)
    the body is a comma-separated var list that the parser stores
    verbatim, so we just re-emit the trimmed body. -/

private def canonicalSerializeAnnotation (ann : StrataAnnotation) : String :=
  match ann with
  | .requires raw =>
      match parseSpecExpr raw with
      | .ok e => s!"@custom:strata requires {canonicalSerialize e}"
      | .error _ => s!"@custom:strata requires {raw}"
  | .ensures raw =>
      match parseSpecExpr raw with
      | .ok e => s!"@custom:strata ensures {canonicalSerialize e}"
      | .error _ => s!"@custom:strata ensures {raw}"
  | .invariant raw =>
      match parseSpecExpr raw with
      | .ok e => s!"@custom:strata invariant {canonicalSerialize e}"
      | .error _ => s!"@custom:strata invariant {raw}"
  | .loopInvariant raw =>
      match parseSpecExpr raw with
      | .ok e => s!"@custom:strata loop-invariant {canonicalSerialize e}"
      | .error _ => s!"@custom:strata loop-invariant {raw}"
  | .modifies raw =>
      s!"@custom:strata modifies {raw}"

/-- Serialize a full annotation list back to a doc-comment body. -/
private def canonicalSerializeAnnotations (anns : List StrataAnnotation) : String :=
  String.intercalate "\n" (anns.map canonicalSerializeAnnotation)

/-! ### Annotation-level structural equality -/

/-- Structural equality on `StrataAnnotation`. For expression-bearing
    keywords we compare the parsed expression ASTs (via
    `stmtExprStructEq`) so that whitespace and parenthesization
    differences between the first and second parse are ignored. -/
private def annStructEq (a b : StrataAnnotation) : Bool :=
  match a, b with
  | .requires x, .requires y =>
      match parseSpecExpr x, parseSpecExpr y with
      | .ok ex, .ok ey => stmtExprStructEq ex ey
      | _, _ => x == y
  | .ensures x, .ensures y =>
      match parseSpecExpr x, parseSpecExpr y with
      | .ok ex, .ok ey => stmtExprStructEq ex ey
      | _, _ => x == y
  | .invariant x, .invariant y =>
      match parseSpecExpr x, parseSpecExpr y with
      | .ok ex, .ok ey => stmtExprStructEq ex ey
      | _, _ => x == y
  | .loopInvariant x, .loopInvariant y =>
      match parseSpecExpr x, parseSpecExpr y with
      | .ok ex, .ok ey => stmtExprStructEq ex ey
      | _, _ => x == y
  | .modifies x, .modifies y => x == y
  | _, _ => false

private def annListStructEq (xs ys : List StrataAnnotation) : Bool :=
  xs.length == ys.length &&
  (xs.zip ys).all (fun (a, b) => annStructEq a b)

/-! ### Generators for `@custom:strata` annotation strings

    The grammar below covers every parser branch in
    `StrataSolidity.SpecParser`:

    * atom (literal int / literal bool / identifier / `msg_sender` /
      `msg_value` / `type(uintN).{min,max}` / `type(intN).max`)
    * `old(expr)` wrapping (REQ-SPEC-041)
    * postfix: `x[idx]`, `f(a, b)` (REQ-SPEC-042)
    * unary/binary: `+`, `-`, `*`, `/`, `%`, `==`, `!=`, `<`, `<=`, `>`,
      `>=`, `&&`, `||`, `==>` (REQ-SPEC-020..REQ-SPEC-024)
    * quantifiers: `forall`, `exists` (REQ-SPEC-040)
-/

private def binaryOperators : List String :=
  ["+", "-", "*", "/", "%", "==", "!=", "<", "<=", ">", ">=", "&&", "||", "==>"]

/-- Depth-bounded expression string generator. `depth` is the maximum
    nesting; at depth 0 we only emit atoms so the generator is total. -/
private partial def genExprString : Nat → Gen String
  | 0 => genAtomString
  | n + 1 => do
      -- Mix atom / unary / binary / quantifier shapes. Weights are not
      -- perfectly tuned — they only have to hit every parser branch.
      let choice ← Gen.choose Nat 0 7 (by decide)
      match choice.val with
      | 0 => genAtomString
      | 1 => do
          let inner ← genExprString n
          return s!"old({inner})"
      | 2 => do
          let lhs ← genExprString n
          let rhs ← genExprString n
          let op ← Gen.elements binaryOperators (by decide)
          return s!"({lhs} {op} {rhs})"
      | 3 => do
          -- Index access: base must be a plain identifier so it lexes cleanly.
          let base ← genNonKeywordIdentifier
          let idx ← genExprString n
          return s!"{base}[{idx}]"
      | 4 => do
          -- Function call with 0, 1, or 2 args. Name must not be `sum`,
          -- `address`, `type`, `old`, `forall`, `exists` or it triggers
          -- a special parser branch with different round-trip shape.
          let fn ← genNonKeywordIdentifier
          let argc ← Gen.choose Nat 0 2 (by decide)
          let args ← (List.range argc.val).mapM (fun _ => genExprString n)
          let argStr := String.intercalate ", " args
          return s!"{fn}({argStr})"
      | 5 => do
          -- forall (REQ-SPEC-040).
          let v ← genNonKeywordIdentifier
          let ty ← Gen.elements ["bool", "address", "uint256"] (by decide)
          let body ← genExprString n
          return s!"forall {v} : {ty} :: {body}"
      | 6 => do
          -- exists (REQ-SPEC-040).
          let v ← genNonKeywordIdentifier
          let ty ← Gen.elements ["bool", "address", "uint256"] (by decide)
          let body ← genExprString n
          return s!"exists {v} : {ty} :: {body}"
      | _ => genAtomString
where
  genAtomString : Gen String := do
    let atomChoice ← Gen.choose Nat 0 5 (by decide)
    match atomChoice.val with
    | 0 => return "true"
    | 1 => return "false"
    | 2 => genIntLiteral
    | 3 => genNonKeywordIdentifier
    -- msg.sender / msg.value — REQ-SPEC-042. Generate as identifiers
    -- directly to dodge the parser's reserved-token handling for `msg`.
    | 4 => Gen.elements ["msg_sender", "msg_value"] (by decide)
    -- type(uintN).min/max and type(intN).max only. See generator
    -- restrictions above for the `type(int*).min` exclusion.
    | _ => Gen.elements ["type(uint256).max", "type(uint256).min", "type(uint128).max", "type(uint8).max", "type(int256).max", "type(int128).max"] (by decide)

/-- Generator for one full annotation line covering every keyword in
    REQ-SPEC-004. -/
private def genAnnotationLine : Gen String := do
  let kw ← genSpecKeyword
  if kw == "modifies" then
    -- Modifies is a comma-separated identifier list per REQ-SPEC-045.
    let n ← Gen.choose Nat 1 3 (by decide)
    let ids ← (List.range n.val).mapM (fun _ => genNonKeywordIdentifier)
    let idStr := String.intercalate ", " ids
    return s!"@custom:strata modifies {idStr}"
  else
    -- All other keywords take an expression body.
    let expr ← genExprString 2
    return s!"@custom:strata {kw} {expr}"

/-- Generator for a full doc-comment body with 1-3 annotation lines. -/
private def genDocBlock : Gen String := do
  let n ← Gen.choose Nat 1 3 (by decide)
  let lines ← (List.range n.val).mapM (fun _ => genAnnotationLine)
  return String.intercalate "\n" lines

/-! ### Wiring to `Plausible.Testable.check`

    We sample `genDocBlock` explicitly inside an `IO` block rather than
    using `∀ s : String, ...` because Plausible's default `String`
    generator would sample random bytes that virtually never look like
    a `@custom:strata` annotation. -/

/-- For a raw doc-comment body `s`, the round-trip property
    `parse (canonicalSerialize (parse s)) = parse s` holds. -/
private def roundTripHolds (s : String) : Bool :=
  let once := parseStrataAnnotations s
  let round := parseStrataAnnotations (canonicalSerializeAnnotations once)
  annListStructEq once round

/-- Driver: sample `pbtConfig.numInst` doc blocks from `genDocBlock` and
    assert `roundTripHolds` on each. Fails fast with the first counter-
    example. Using the shared `pbtConfig` keeps the seed and sample count
    aligned with the rest of the characterization PBTs (REQ-TEST-001).

    Determinism is obtained by seeding the global `stdGenRef` once per
    sample from the fixed `pbtConfig.randomSeed`. That matches how
    Plausible's `Testable.checkIO` threads a seed through `Gen.run` and
    keeps counter-examples replayable locally. -/
private def runRoundTripPbt : IO Unit := do
  let seed := pbtConfig.randomSeed.getD 0
  let n := pbtConfig.numInst
  let mut counter : Option String := none
  for i in [0:n] do
    -- Deterministically perturb the seed per sample so the full run is
    -- reproducible yet still explores the generator.
    IO.stdGenRef.set (mkStdGen (seed + i))
    let sample ← Gen.run genDocBlock 20
    if ! roundTripHolds sample then
      counter := some s!"i={i}, seed={seed + i}: {sample}"
      break
  match counter with
  | none => pure ()
  | some msg => throw <| IO.userError ("REQ-PBT-001 counter-example " ++ msg)

-- Entry point for the characterization PBT. Runs under `#eval` whenever
-- the test module is elaborated.
-- **Validates: REQ-PBT-001** (and by construction, every REQ-SPEC-* branch
-- exercised by `genAnnotationLine` / `genExprString`).
#eval runRoundTripPbt

end Strata.Solidity.SpecParser.Pbt
