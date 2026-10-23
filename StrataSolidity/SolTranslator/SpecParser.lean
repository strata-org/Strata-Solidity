/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

import StrataSolidity.SolTranslator.Types
import StrataSolidity.SolcAstParser

namespace Strata.Solidity
open Laurel

/-! ## Specification Extraction Helpers -/

/-- A parsed `@custom:strata` annotation. -/
inductive StrataAnnotation where
  | requires (expr : String)
  | ensures (expr : String)
  | invariant (expr : String)
  | modifies (vars : String)
  | loopInvariant (expr : String)

/-- The NatSpec tag that introduces a StrataSolidity annotation. -/
def strataTag : String := "@custom:strata"

/-- Split off leading whitespace and NatSpec comment markers (`/`, `*`):
    `("   /// ", "@custom:strata …")`. -/
def splitCommentLead (line : String) : String × String :=
  let chars := line.toList
  let lead := chars.takeWhile fun c => c == ' ' || c == '\t' || c == '/' || c == '*'
  (String.ofList lead, String.ofList (chars.drop lead.length))

/-- If `line` (comment markers already removed) is an annotation line — the
    tag followed by whitespace or the end of the line, as in NatSpec tag
    syntax — the trimmed text after the tag (`""` for a bare tag). -/
def afterStrataTag? (line : String) : Option String :=
  if line.startsWith strataTag then
    let rest := (line.drop strataTag.length).toString
    match rest.toList.head? with
    | none => some ""
    | some c => if c == ' ' || c == '\t' then some rest.trimAscii.toString else none
  else none

/-- The text after the tag on every annotation line of a NatSpec
    documentation string, trimmed. -/
def strataAnnotationLines (doc : String) : List String :=
  (doc.splitOn "\n").filterMap fun line => afterStrataTag? (splitCommentLead line).2

/-- Indices (into `strataAnnotationLines doc`) of annotations followed by a
    non-empty line that is not a NatSpec tag. NatSpec continues a tag's text
    on such lines, but StrataSolidity reads one line per annotation, so that
    text would otherwise be dropped silently. -/
def continuedStrataAnnotations (doc : String) : List Nat := Id.run do
  let mut out : List Nat := []
  let mut idx := 0
  let mut open? : Option Nat := none
  for line in doc.splitOn "\n" do
    let text := (splitCommentLead line).2.trimAscii.toString
    match afterStrataTag? text with
    | some _ =>
      open? := some idx
      idx := idx + 1
    | none =>
      if let some i := open? then
        if !text.isEmpty && !text.startsWith "@" && !out.contains i then out := out ++ [i]
      if text.isEmpty || text.startsWith "@" then open? := none
  return out

/-- Parse the text after `@custom:strata` as `<keyword> <body>` (separated
    by spaces or tabs). Returns `none` for an unknown keyword or an empty
    body. -/
def parseStrataAnnotation? (rest : String) : Option StrataAnnotation :=
  let chars := rest.toList
  let kw := String.ofList (chars.takeWhile fun c => c != ' ' && c != '\t')
  let body := (String.ofList (chars.drop kw.length)).trimAscii.toString
  if body.isEmpty then none
  else match kw with
    | "requires" => some (.requires body)
    | "ensures" => some (.ensures body)
    | "invariant" => some (.invariant body)
    | "modifies" => some (.modifies body)
    | "loop-invariant" => some (.loopInvariant body)
    | _ => none

/-- Parse `@strata` (or legacy `@custom:strata`) annotations from a NatSpec documentation string.
    Each line matching `@strata <keyword> <expr>` produces an annotation. -/
def parseStrataAnnotations (doc : String) : List StrataAnnotation :=
  (strataAnnotationLines doc).filterMap parseStrataAnnotation?

/-- `@custom:strata` lines whose keyword is not recognized (typos such as
    `ensure`, or unsupported annotations such as `lemma`). These are not
    verified, so the caller reports them. -/
def unrecognizedStrataAnnotations (doc : String) : List String :=
  (strataAnnotationLines doc).filter (parseStrataAnnotation? · |>.isNone)

/-- A comment of a Solidity source: the byte range of its text (after the
    opening `//`, `///`, `/*` or `/**`, before a closing `*/`) and its
    opening marker. -/
structure CommentSpan where
  start : Nat
  stop : Nat
  marker : String

/-- The comments of `source`, in order. String literals are skipped, so a
    tag inside a string is not in a comment. -/
def commentSpans (source : String) : List CommentSpan := Id.run do
  let b := source.toUTF8
  let n := b.size
  let byte (k : Nat) : UInt8 := if k < n then b[k]! else 0
  let mut out : List CommentSpan := []
  let mut i := 0
  let mut fuel := n + 1
  while i < n && fuel > 0 do
    fuel := fuel - 1
    let c := byte i
    if c == 34 || c == 39 then  -- '"' or '\''
      -- A string literal ends byte the matching quote or the end of the line.
      let mut k := i + 1
      while k < n && byte k != c && byte k != 10 do
        k := if byte k == 92 then k + 2 else k + 1  -- '\\' escapes
      i := k + 1
    else if c == 47 && byte (i + 1) == 47 then  -- `//`
      let marker := if byte (i + 2) == 47 then "///" else "//"
      let mut k := i + 2
      while k < n && byte k != 10 do k := k + 1
      out := out ++ [{ start := i + marker.length, stop := k, marker }]
      i := k
    else if c == 47 && byte (i + 1) == 42 then  -- `/*`
      let marker := if byte (i + 2) == 42 && byte (i + 3) != 47 then "/**" else "/*"
      let mut k := i + 2
      while k < n && !(byte k == 42 && byte (k + 1) == 47) do k := k + 1
      out := out ++ [{ start := i + marker.length, stop := k, marker }]
      i := k + 2
    else i := i + 1
  return out

/-- The lines of every comment of `source`, as (range of the line's text
    after leading whitespace — and a block comment's leading `*`s — up to
    the end of the line, the comment's opening marker). -/
def commentLines (source : String) : List (SourceRange × String) := Id.run do
  let b := source.toUTF8
  let byte (k : Nat) : UInt8 := if k < b.size then b[k]! else 0
  let mut out : List (SourceRange × String) := []
  for cmt in commentSpans source do
    let mut ls := cmt.start
    let mut first := true
    let mut fuel := cmt.stop - cmt.start + 2
    while ls <= cmt.stop && fuel > 0 do
      fuel := fuel - 1
      let mut le := ls
      while le < cmt.stop && byte le != 10 do le := le + 1
      let stop := if le > ls && byte (le - 1) == 13 then le - 1 else le
      let mut k := ls
      while k < stop && (byte k == 32 || byte k == 9 ||
          (!first && cmt.marker.startsWith "/*" && byte k == 42)) do
        k := k + 1
      if k < stop then out := out ++ [({ start := ⟨k⟩, stop := ⟨stop⟩ }, cmt.marker)]
      first := false
      ls := le + 1
  return out

/-- The text of `source` in `r`. -/
def textAt (source : String) (r : SourceRange) : String :=
  String.fromUTF8! (source.toUTF8.extract r.start.byteIdx r.stop.byteIdx)

/-- Every annotation line of `source`: a comment line whose text starts
    with the tag as `strataAnnotationLines` requires, as (range from the tag
    to the end of the line, the comment's opening marker). Trailing comments
    count (`uint256 x; /// @custom:strata …`); a tag in prose or in a string
    literal does not. -/
def annotationLinesInSource (source : String) : List (SourceRange × String) :=
  (commentLines source).filter fun (r, _) => (afterStrataTag? (textAt source r)).isSome

/-- Tags in the middle of a NatSpec comment line (`/// Sets x.
    @custom:strata …`). solc reads them as NatSpec tags, but an annotation
    must start its line, so these are not verified. (In a plain `//`
    comment, the tag is only prose.) -/
def midlineTagsInSource (source : String) : List SourceRange :=
  (commentLines source).flatMap fun (r, marker) =>
    if marker != "///" && marker != "/**" then [] else
    let parts := (textAt source r).splitOn strataTag
    -- The tag after each part but the last, at its byte offset in the line;
    -- one at offset 0 starts an annotation line.
    let (_, tags) := parts.dropLast.foldl (fun (off, acc) part =>
      let tagOff := off + part.utf8ByteSize
      let afterSpace := !part.isEmpty && (part.back == ' ' || part.back == '\t')
      let acc := if tagOff > 0 && afterSpace then
          acc ++ [({ start := ⟨r.start.byteIdx + tagOff⟩,
                     stop := ⟨r.start.byteIdx + tagOff + strataTag.utf8ByteSize⟩ } : SourceRange)]
        else acc
      (tagOff + strataTag.utf8ByteSize, acc)) (0, [])
    tags

/-- Whether two source ranges share a byte. -/
def rangesOverlap (a b : SourceRange) : Bool :=
  a.start.byteIdx < b.stop.byteIdx && b.start.byteIdx < a.stop.byteIdx

/-- Byte ranges of the annotation lines of the comment at `docRange` in
    `source`, in order (see `annotationLinesInSource`). -/
def annotationLineRanges (source : String) (docRange : SourceRange) : List SourceRange :=
  ((annotationLinesInSource source).map (·.1)).filter (rangesOverlap · docRange)

/-- `strataAnnotationLines` of a NatSpec comment, each paired with its source
    range when the comment can be located in `source?`; otherwise every line
    gets the comment's (or its declaration's) range `doc.ann`. -/
def strataAnnotationLinesAt (source? : Option String) (doc : StrataDDM.Ann String SourceRange)
    : List (String × SourceRange) :=
  let lines := strataAnnotationLines doc.val
  let ranges := match source? with
    | some src => annotationLineRanges src doc.ann
    | none => []
  if ranges.length == lines.length then lines.zip ranges
  else lines.map (·, doc.ann)

/-- `parseStrataAnnotations` with the source range of each annotation line. -/
def parseStrataAnnotationsAt (source? : Option String) (doc : StrataDDM.Ann String SourceRange)
    : List (StrataAnnotation × SourceRange) :=
  (strataAnnotationLinesAt source? doc).filterMap fun (line, r) =>
    (parseStrataAnnotation? line).map (·, r)

/-- `unrecognizedStrataAnnotations` with the source range of each line. -/
def unrecognizedStrataAnnotationsAt (source? : Option String)
    (doc : StrataDDM.Ann String SourceRange) : List (String × SourceRange) :=
  (strataAnnotationLinesAt source? doc).filter fun (line, _) =>
    (parseStrataAnnotation? line).isNone

/-- The keyword of an annotation, as written after `@custom:strata`. -/
def StrataAnnotation.keyword : StrataAnnotation → String
  | .requires _ => "requires"
  | .ensures _ => "ensures"
  | .invariant _ => "invariant"
  | .modifies _ => "modifies"
  | .loopInvariant _ => "loop-invariant"

/-! ## Spec Expression Parser

Recursive descent parser for `@custom:strata` annotation expressions.
Supports: identifiers, integer literals, `true`/`false`, `old(expr)`,
`msg.sender`, `msg.value`, member access (`x.y`), index access (`x[y]`),
binary operators (`==`, `!=`, `>=`, `<=`, `>`, `<`, `+`, `-`, `*`),
boolean operators (`&&`, `||`), and parentheses.
-/

namespace SpecParser

set_option linter.deprecated false in
/-- Tokenize a spec expression string into a list of tokens. -/
def tokenize (s : String) : List String :=
  -- Identifiers get the same `$` renaming as the AST (`SolcAst.mangleName`).
  (tokenizeRaw s).map SolcAst.mangleName
where
  tokenizeRaw (s : String) : List String :=
  let rec go (i : Nat) (acc : List String) (cur : String) (fuel : Nat) : List String :=
    if fuel == 0 then (if cur.isEmpty then acc else acc ++ [cur]).reverse
    else if i >= s.length then (if cur.isEmpty then acc else acc ++ [cur])
    else
      let c := s.get ⟨i⟩
      if c == ' ' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 1) acc' "" (fuel - 1)
      else if c == '(' || c == ')' || c == '[' || c == ']' || c == ',' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 1) (acc' ++ [c.toString]) "" (fuel - 1)
      else if c == '=' && i + 1 < s.length && s.get ⟨i+1⟩ == '=' && i + 2 < s.length && s.get ⟨i+2⟩ == '>' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 3) (acc' ++ ["==>"]) "" (fuel - 1)
      else if c == '=' && i + 1 < s.length && s.get ⟨i+1⟩ == '=' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 2) (acc' ++ ["=="]) "" (fuel - 1)
      else if c == '!' && i + 1 < s.length && s.get ⟨i+1⟩ == '=' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 2) (acc' ++ ["!="]) "" (fuel - 1)
      else if c == '!' then
        -- Standalone logical-not. Emitted as its own token so the parser's
        -- unary layer (parseUnary) can pick it up; without this, a bare `!`
        -- would accumulate into the following identifier (e.g. `!paused`).
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 1) (acc' ++ ["!"]) "" (fuel - 1)
      else if c == '>' && i + 1 < s.length && s.get ⟨i+1⟩ == '=' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 2) (acc' ++ [">="]) "" (fuel - 1)
      else if c == '<' && i + 1 < s.length && s.get ⟨i+1⟩ == '=' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 2) (acc' ++ ["<="]) "" (fuel - 1)
      else if c == '&' && i + 1 < s.length && s.get ⟨i+1⟩ == '&' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 2) (acc' ++ ["&&"]) "" (fuel - 1)
      else if c == '|' && i + 1 < s.length && s.get ⟨i+1⟩ == '|' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 2) (acc' ++ ["||"]) "" (fuel - 1)
      else if c == ':' && i + 1 < s.length && s.get ⟨i+1⟩ == ':' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 2) (acc' ++ ["::"]) "" (fuel - 1)
      else if c == ':' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 1) (acc' ++ [":"]) "" (fuel - 1)
      else if c == '>' || c == '<' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 1) (acc' ++ [c.toString]) "" (fuel - 1)
      else if c == '+' || c == '-' || c == '*' || c == '/' || c == '%' || c == '.' then
        let acc' := if cur.isEmpty then acc else acc ++ [cur]
        go (i + 1) (acc' ++ [c.toString]) "" (fuel - 1)
      else
        go (i + 1) acc (cur.push c) (fuel - 1)
  go 0 [] "" (s.length * 4 + 10)

private def isDigitStr (s : String) : Bool :=
  !s.isEmpty && s.toList.all Char.isDigit

/-- Try to parse a scientific notation token like "1e24" → some (1 * 10^24). -/
private def parseSciNotation (s : String) : Option Nat :=
  match s.splitOn "e" with
  | [base, exp] =>
    if isDigitStr base && isDigitStr exp then
      match base.toNat?, exp.toNat? with
      | some b, some e => some (b * 10 ^ e)
      | _, _ => none
    else none
  | _ => none

/-- Map a Solidity type name string to a Laurel HighType (for quantifier bindings). -/
private def solTypeNameToHighType (name : String) : HighType :=
  if name == "bool" then .TBool
  else if name == "address" then .TInt
  else .TInt  -- uint256, int256, etc. all map to TInt

/-- Compute the integer value of `type(T).min` or `type(T).max` for elementary integer types. -/
def typeMinMax (typeName : String) (member : String) : Option Int :=
  let parseBits (pfx : String) (default : Nat) : Option Nat :=
    let suffix := typeName.drop pfx.length
    if suffix.isEmpty then some default
    else suffix.toNat?
  if typeName.startsWith "uint" then do
    let bits ← parseBits "uint" 256
    if member == "min" then some 0
    else some (2 ^ bits - 1)  -- max
  else if typeName.startsWith "int" then do
    let bits ← parseBits "int" 256
    if member == "min" then some (-(2 ^ (bits - 1)))
    else some (2 ^ (bits - 1) - 1)  -- max
  else none

/-- Parse a spec expression string into a Laurel StmtExprMd.
    Returns the parsed expression and remaining tokens. -/
partial def parseExpr (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
  parseImplies tokens

where
  parseImplies (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseOr tokens
    match rest with
    | "==>" :: rest' =>
      let (rhs, rest'') ← parseImplies rest'
      return (mkStmtExprMd (mkPrimOp .Implies [lhs, rhs]), rest'')
    | _ => return (lhs, rest)

  parseOr (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseAnd tokens
    match rest with
    | "||" :: rest' =>
      let (rhs, rest'') ← parseOr rest'
      return (mkStmtExprMd (mkPrimOp .OrElse [lhs, rhs]), rest'')
    | _ => return (lhs, rest)

  parseAnd (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseComparison tokens
    match rest with
    | "&&" :: rest' =>
      let (rhs, rest'') ← parseAnd rest'
      return (mkStmtExprMd (mkPrimOp .AndThen [lhs, rhs]), rest'')
    | _ => return (lhs, rest)

  parseComparison (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseAddSub tokens
    match rest with
    | "==" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (mkPrimOp .Eq [lhs, rhs]), rest'')
    | "!=" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (mkPrimOp .Neq [lhs, rhs]), rest'')
    | ">=" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (mkPrimOp .Geq [lhs, rhs]), rest'')
    | "<=" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (mkPrimOp .Leq [lhs, rhs]), rest'')
    | ">" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (mkPrimOp .Gt [lhs, rhs]), rest'')
    | "<" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (mkPrimOp .Lt [lhs, rhs]), rest'')
    | _ => return (lhs, rest)

  parseAddSub (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseMul tokens
    parseAddSubTail lhs rest

  parseAddSubTail (lhs : StmtExprMd) (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    match tokens with
    | "+" :: rest =>
      let (rhs, rest') ← parseMul rest
      parseAddSubTail (mkStmtExprMd (mkPrimOp .Add [lhs, rhs])) rest'
    | "-" :: rest =>
      let (rhs, rest') ← parseMul rest
      parseAddSubTail (mkStmtExprMd (mkPrimOp .Sub [lhs, rhs])) rest'
    | _ => return (lhs, tokens)

  parseMul (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseUnary tokens
    parseMulTail lhs rest

  parseMulTail (lhs : StmtExprMd) (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    match tokens with
    | "*" :: rest =>
      let (rhs, rest') ← parseUnary rest
      parseMulTail (mkStmtExprMd (mkPrimOp .Mul [lhs, rhs])) rest'
    -- Solidity's `/` rounds toward zero and `%` takes the sign of the
    -- dividend (`-7 / 2 == -3`, `-7 % 2 == -1`): the truncating operations,
    -- as in function bodies. For non-negative operands they agree with the
    -- Euclidean ones.
    | "/" :: rest =>
      let (rhs, rest') ← parseUnary rest
      parseMulTail (mkStmtExprMd (mkPrimOp .DivT [lhs, rhs])) rest'
    | "%" :: rest =>
      let (rhs, rest') ← parseUnary rest
      parseMulTail (mkStmtExprMd (mkPrimOp .ModT [lhs, rhs])) rest'
    | _ => return (lhs, tokens)

  -- Prefix unary layer (`unary ::= ("!" | "-")? postfix` in SpecGrammar.lean).
  -- Mirrors the body-expression handling in ExprTranslator.lean: `!` becomes a
  -- logical `Not`, `-` an arithmetic `Neg`. A unary minus directly on an integer
  -- literal is folded to a negative `LiteralInt` (e.g. tick bounds like `-887272`)
  -- so the common case never relies on downstream `Neg` handling.
  parseUnary (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    match tokens with
    | "!" :: rest =>
      let (operand, rest') ← parseUnary rest
      return (mkStmtExprMd (mkPrimOp .Not [operand]), rest')
    | "-" :: rest =>
      let (operand, rest') ← parseUnary rest
      let neg := match operand.val with
        | .LiteralInt n => mkStmtExprMd (.LiteralInt (-n))
        | _ => mkStmtExprMd (mkPrimOp .Neg [operand])
      return (neg, rest')
    | _ => parsePostfix tokens

  parsePostfix (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (base, rest) ← parseAtom tokens
    parsePostfixTail base rest

  parseArgList (tokens : List String) : Except TranslationError (List StmtExprMd × List String) := do
    match tokens with
    | ")" :: rest => return ([], rest)
    | _ =>
      let (arg, rest) ← parseExpr tokens
      let rec go (acc : List StmtExprMd) (toks : List String) : Except TranslationError (List StmtExprMd × List String) := do
        match toks with
        | ")" :: rest => return (acc.reverse, rest)
        | "," :: rest =>
          let (arg, rest') ← parseExpr rest
          go (arg :: acc) rest'
        | _ => throw (.typeError "Expected ')' or ',' in argument list")
      go [arg] rest

  parsePostfixTail (base : StmtExprMd) (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    match tokens with
    | "[" :: rest =>
      let (idx, rest') ← parseExpr rest
      match rest' with
      | "]" :: rest'' =>
        let sel := mkStmtExprMd (mkCall "select" [base, idx])
        parsePostfixTail sel rest''
      | _ => throw (.typeError "Expected ']' in index access")
    | "(" :: rest =>
      -- Function call: base(arg1, arg2, ...) or obj.method(arg1, ...)
      let fname := match base.val with
        | .Var (.Local name) => name.text
        | .Var (.Field obj field) =>
          -- obj.method → "obj_method" for Strata builtins (abi.encodePacked → abi_encodePacked)
          match obj.val with
          | .Var (.Local objName) => s!"{objName.text}_{field.text}"
          | _ => s!"__unknown_{field.text}"
        | _ => "__unknown_call"
      let (args, rest') ← parseArgList rest
      -- Dispatch multi-arg builtins: abi_encode(a,b) → abi_encode2(a,b)
      -- Dispatch sum(mapping) → sum_<mapping>(mapping)
      let fname' := if fname == "sum" && args.length == 1 then
        match args.head?.map (·.val) with
        | some (.Var (.Local name)) => s!"sum_{name.text}"
        | _ => fname
      else if args.length > 1 && (fname == "abi_encodePacked" || fname == "abi_encode") then
        s!"{fname}{args.length}"
      else fname
      let call := mkStmtExprMd (mkCall fname' args)
      parsePostfixTail call rest'
    | "." :: member :: rest =>
      if member == "length" then
        -- x.length → Identifier "x_length" (for arrays)
        match base.val with
        | .Var (.Local name) =>
          parsePostfixTail (mkStmtExprMd (mkIdentifier s!"{name.text}_length")) rest
        | _ => throw (.typeError "length access on non-identifier")
      else
        parsePostfixTail (mkStmtExprMd (mkFieldSelect base member)) rest
    | _ => return (base, tokens)

  parseAtom (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    -- `block.timestamp`, `tx.origin`, …: constants of the transaction
    if let base :: "." :: member :: rest := tokens then
      if let some (c, _) := envConstants.find? (·.2.1 == s!"{base}.{member}") then
        return (mkStmtExprMd (mkCall c []), rest)
    match tokens with
    | [] => throw (.typeError "Unexpected end of spec expression")
    | "(" :: rest =>
      let (inner, rest') ← parseExpr rest
      match rest' with
      | ")" :: rest'' => return (inner, rest'')
      | _ => throw (.typeError "Expected ')' in spec expression")
    | "true" :: rest => return (mkStmtExprMd (.LiteralBool true), rest)
    | "false" :: rest => return (mkStmtExprMd (.LiteralBool false), rest)
    -- The contract's address: a constant (see `envConstants`)
    | "this" :: rest => return (mkStmtExprMd (mkCall "this_address" []), rest)
    | "old" :: "(" :: rest =>
      let (inner, rest') ← parseExpr rest
      match rest' with
      | ")" :: rest'' =>
        -- Mark old() expressions with a StaticCall "__old" so they can be
        -- identified and rewritten by processOldMarkers later.
        return (mkStmtExprMd (mkCall "__old" [inner]), rest'')
      | _ => throw (.typeError "Expected ')' after old(")
    | "address" :: "(" :: rest =>
      -- address(expr) is a type cast to address; treat as identity on the inner expr
      let (inner, rest') ← parseExpr rest
      match rest' with
      | ")" :: rest'' => return (inner, rest'')
      | _ => throw (.typeError "Expected ')' after address(")
    | "msg" :: "." :: "sender" :: rest =>
      return (mkStmtExprMd (mkIdentifier "msg_sender"), rest)
    | "msg" :: "." :: "value" :: rest =>
      return (mkStmtExprMd (mkIdentifier "msg_value"), rest)
    | "type" :: "(" :: typeName :: ")" :: "." :: member :: rest =>
      match typeMinMax typeName member with
      | some v => return (mkStmtExprMd (.LiteralInt v), rest)
      | none => throw (.typeError s!"Unknown type member: type({typeName}).{member}")
    -- A bound variable ranges over the values of its Solidity type
    -- (`uint8`: 0..255, `address`: 0..2^160-1, …), not over all integers:
    -- `forall v : T :: P` means `forall v :: inRange(v) ==> P`, and
    -- `exists v : T :: P` means `exists v :: inRange(v) && P`. Without the
    -- range, `exists i : uint8 :: i == k` was proven for every uint256 `k`.
    | "forall" :: varName :: ":" :: typeName :: "::" :: rest =>
      let ty := solTypeNameToHighType typeName
      let param : Parameter := { name := varName, type := mkHighTypeMd ty }
      let (body, rest') ← parseExpr rest
      let body := match mkRangeCond typeName (mkStmtExprMd (mkIdentifier varName)) with
        | some range => mkStmtExprMd (mkPrimOp .Implies [range, body])
        | none => body
      return (mkStmtExprMd (mkForall param body), rest')
    | "exists" :: varName :: ":" :: typeName :: "::" :: rest =>
      let ty := solTypeNameToHighType typeName
      let param : Parameter := { name := varName, type := mkHighTypeMd ty }
      let (body, rest') ← parseExpr rest
      let body := match mkRangeCond typeName (mkStmtExprMd (mkIdentifier varName)) with
        | some range => mkStmtExprMd (mkPrimOp .And [range, body])
        | none => body
      return (mkStmtExprMd (mkExists param body), rest')
    | tok :: rest =>
      if isDigitStr tok then
        match tok.toNat? with
        | some n => return (mkStmtExprMd (.LiteralInt n), rest)
        | none => throw (.typeError s!"Invalid integer literal: {tok}")
      else match parseSciNotation tok with
        | some n => return (mkStmtExprMd (.LiteralInt n), rest)
        | none => return (mkStmtExprMd (mkIdentifier tok), rest)

/-- The entries of a `modifies` annotation, as (variable, key text): `x`,
    `m[k]`, separated by commas outside brackets and parentheses (a key may
    contain commas: `positions[keccak256(abi.encodePacked(a, b))]`). Only
    the first `[` separates the variable from its key, which runs to the
    final `]`. -/
def modifiesEntries (s : String) : List (String × Option String) :=
  let splitTopLevel (s : String) : List String := Id.run do
    let mut out : List String := []
    let mut cur : String := ""
    let mut depth : Nat := 0
    for c in s.toList do
      if c == '[' || c == '(' then
        depth := depth + 1; cur := cur.push c
      else if c == ']' || c == ')' then
        depth := depth - 1; cur := cur.push c
      else if c == ',' && depth == 0 then
        out := out ++ [cur]; cur := ""
      else
        cur := cur.push c
    if !cur.toSlice.trimAscii.isEmpty then out := out ++ [cur]
    return out
  (splitTopLevel s).map fun entry =>
    let entry := entry.trimAscii.toString
    match entry.toList.findIdx? (· == '[') with
    | none => (SolcAst.mangleName entry, none)
    | some i =>
      let base := SolcAst.mangleName (entry.take i).trimAscii.toString
      let keyPart := entry.drop (i+1) |>.dropEnd 1  -- strip trailing ]
      (base, some keyPart.trimAscii.toString)

/-- The keys of a `modifies` annotation that cannot be read as one spec
    expression: with such a key, the frame of its mapping is not checked. -/
def unreadableModifiesKeys (s : String) : List (String × String) :=
  (modifiesEntries s).filterMap fun
    | (base, some key) => match parseExpr (tokenize key) with
      | .ok (_, []) => none
      | _ => some (base, key)
    | _ => none

end SpecParser

/-- Parse a spec expression string into a Laurel StmtExprMd. -/
def parseSpecExpr (s : String) : Except TranslationError StmtExprMd := do
  let tokens := SpecParser.tokenize s
  let (expr, rest) ← SpecParser.parseExpr tokens
  if !rest.isEmpty then
    throw (.typeError s!"Unexpected tokens after spec expression: {rest}")
  return expr


end Strata.Solidity
