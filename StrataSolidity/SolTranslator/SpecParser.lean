import StrataSolidity.SolTranslator.Types

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

/-- Parse `@strata` (or legacy `@custom:strata`) annotations from a NatSpec documentation string.
    Each line matching `@strata <keyword> <expr>` produces an annotation. -/
def parseStrataAnnotations (doc : String) : List StrataAnnotation :=
  let lines := doc.splitOn "\n" |>.map String.trim
  lines.filterMap fun line =>
    let tag := "@custom:strata "
    let mtag := "* @custom:strata "
    let rest? := if line.startsWith tag then
        some ((line.drop tag.length).toString.trim)
      else if line.startsWith mtag then
        some ((line.drop mtag.length).toString.trim)
      else none
    match rest? with
    | none => none
    | some rest =>
      if rest.startsWith "requires " then
        some (.requires ((rest.drop "requires ".length).toString.trim))
      else if rest.startsWith "ensures " then
        some (.ensures ((rest.drop "ensures ".length).toString.trim))
      else if rest.startsWith "invariant " then
        some (.invariant ((rest.drop "invariant ".length).toString.trim))
      else if rest.startsWith "modifies " then
        some (.modifies ((rest.drop "modifies ".length).toString.trim))
      else if rest.startsWith "loop-invariant " then
        some (.loopInvariant ((rest.drop "loop-invariant ".length).toString.trim))
      else none

/-! ## Spec Expression Parser

Recursive descent parser for `@custom:strata` annotation expressions.
Supports: identifiers, integer literals, `true`/`false`, `old(expr)`,
`msg.sender`, `msg.value`, member access (`x.y`), index access (`x[y]`),
binary operators (`==`, `!=`, `>=`, `<=`, `>`, `<`, `+`, `-`, `*`),
boolean operators (`&&`, `||`), and parentheses.
-/

namespace SpecParser

/-- Tokenize a spec expression string into a list of tokens. -/
def tokenize (s : String) : List String :=
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
      return (mkStmtExprMd (.PrimitiveOp .Implies [lhs, rhs]), rest'')
    | _ => return (lhs, rest)

  parseOr (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseAnd tokens
    match rest with
    | "||" :: rest' =>
      let (rhs, rest'') ← parseOr rest'
      return (mkStmtExprMd (.PrimitiveOp .Or [lhs, rhs]), rest'')
    | _ => return (lhs, rest)

  parseAnd (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseComparison tokens
    match rest with
    | "&&" :: rest' =>
      let (rhs, rest'') ← parseAnd rest'
      return (mkStmtExprMd (.PrimitiveOp .And [lhs, rhs]), rest'')
    | _ => return (lhs, rest)

  parseComparison (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseAddSub tokens
    match rest with
    | "==" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (.PrimitiveOp .Eq [lhs, rhs]), rest'')
    | "!=" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (.PrimitiveOp .Neq [lhs, rhs]), rest'')
    | ">=" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (.PrimitiveOp .Geq [lhs, rhs]), rest'')
    | "<=" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (.PrimitiveOp .Leq [lhs, rhs]), rest'')
    | ">" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (.PrimitiveOp .Gt [lhs, rhs]), rest'')
    | "<" :: rest' =>
      let (rhs, rest'') ← parseAddSub rest'
      return (mkStmtExprMd (.PrimitiveOp .Lt [lhs, rhs]), rest'')
    | _ => return (lhs, rest)

  parseAddSub (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parseMul tokens
    parseAddSubTail lhs rest

  parseAddSubTail (lhs : StmtExprMd) (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    match tokens with
    | "+" :: rest =>
      let (rhs, rest') ← parseMul rest
      parseAddSubTail (mkStmtExprMd (.PrimitiveOp .Add [lhs, rhs])) rest'
    | "-" :: rest =>
      let (rhs, rest') ← parseMul rest
      parseAddSubTail (mkStmtExprMd (.PrimitiveOp .Sub [lhs, rhs])) rest'
    | _ => return (lhs, tokens)

  parseMul (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    let (lhs, rest) ← parsePostfix tokens
    parseMulTail lhs rest

  parseMulTail (lhs : StmtExprMd) (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    match tokens with
    | "*" :: rest =>
      let (rhs, rest') ← parsePostfix rest
      parseMulTail (mkStmtExprMd (.PrimitiveOp .Mul [lhs, rhs])) rest'
    | "/" :: rest =>
      let (rhs, rest') ← parsePostfix rest
      parseMulTail (mkStmtExprMd (.PrimitiveOp .Div [lhs, rhs])) rest'
    | "%" :: rest =>
      let (rhs, rest') ← parsePostfix rest
      parseMulTail (mkStmtExprMd (.PrimitiveOp .Mod [lhs, rhs])) rest'
    | _ => return (lhs, tokens)

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
        let sel := mkStmtExprMd (.StaticCall "select" [base, idx])
        parsePostfixTail sel rest''
      | _ => throw (.typeError "Expected ']' in index access")
    | "(" :: rest =>
      -- Function call: base(arg1, arg2, ...) or obj.method(arg1, ...)
      let fname := match base.val with
        | .Identifier name => name.text
        | .FieldSelect obj field =>
          -- obj.method → "obj_method" for Strata builtins (abi.encodePacked → abi_encodePacked)
          match obj.val with
          | .Identifier objName => s!"{objName.text}_{field.text}"
          | _ => s!"__unknown_{field.text}"
        | _ => "__unknown_call"
      let (args, rest') ← parseArgList rest
      -- Dispatch multi-arg builtins: abi_encode(a,b) → abi_encode2(a,b)
      -- Dispatch sum(mapping) → sum_<mapping>(mapping)
      let fname' := if fname == "sum" && args.length == 1 then
        match args.head?.map (·.val) with
        | some (.Identifier name) => s!"sum_{name.text}"
        | _ => fname
      else if args.length == 2 && (fname == "abi_encodePacked" || fname == "abi_encode") then
        s!"{fname}2"
      else fname
      let call := mkStmtExprMd (.StaticCall fname' args)
      parsePostfixTail call rest'
    | "." :: member :: rest =>
      if member == "length" then
        -- x.length → Identifier "x_length" (for arrays)
        match base.val with
        | .Identifier name => parsePostfixTail (mkStmtExprMd (.Identifier s!"{name}_length")) rest
        | _ => throw (.typeError "length access on non-identifier")
      else
        parsePostfixTail (mkStmtExprMd (.FieldSelect base ⟨member, none⟩)) rest
    | _ => return (base, tokens)

  parseAtom (tokens : List String) : Except TranslationError (StmtExprMd × List String) := do
    match tokens with
    | [] => throw (.typeError "Unexpected end of spec expression")
    | "(" :: rest =>
      let (inner, rest') ← parseExpr rest
      match rest' with
      | ")" :: rest'' => return (inner, rest'')
      | _ => throw (.typeError "Expected ')' in spec expression")
    | "true" :: rest => return (mkStmtExprMd (.LiteralBool true), rest)
    | "false" :: rest => return (mkStmtExprMd (.LiteralBool false), rest)
    | "old" :: "(" :: rest =>
      let (inner, rest') ← parseExpr rest
      match rest' with
      | ")" :: rest'' =>
        -- Mark old() expressions with a StaticCall "__old" so they can be
        -- identified and rewritten by processOldMarkers later.
        return (mkStmtExprMd (.StaticCall "__old" [inner]), rest'')
      | _ => throw (.typeError "Expected ')' after old(")
    | "address" :: "(" :: rest =>
      -- address(expr) is a type cast to address; treat as identity on the inner expr
      let (inner, rest') ← parseExpr rest
      match rest' with
      | ")" :: rest'' => return (inner, rest'')
      | _ => throw (.typeError "Expected ')' after address(")
    | "msg" :: "." :: "sender" :: rest =>
      return (mkStmtExprMd (.Identifier "msg_sender"), rest)
    | "msg" :: "." :: "value" :: rest =>
      return (mkStmtExprMd (.Identifier "msg_value"), rest)
    | "type" :: "(" :: typeName :: ")" :: "." :: member :: rest =>
      match typeMinMax typeName member with
      | some v => return (mkStmtExprMd (.LiteralInt v), rest)
      | none => throw (.typeError s!"Unknown type member: type({typeName}).{member}")
    | "forall" :: varName :: ":" :: typeName :: "::" :: rest =>
      let ty := solTypeNameToHighType typeName
      let param : Parameter := { name := varName, type := mkHighTypeMd ty }
      let (body, rest') ← parseExpr rest
      return (mkStmtExprMd (.Forall param body), rest')
    | "exists" :: varName :: ":" :: typeName :: "::" :: rest =>
      let ty := solTypeNameToHighType typeName
      let param : Parameter := { name := varName, type := mkHighTypeMd ty }
      let (body, rest') ← parseExpr rest
      return (mkStmtExprMd (.Exists param body), rest')
    | tok :: rest =>
      if isDigitStr tok then
        match tok.toNat? with
        | some n => return (mkStmtExprMd (.LiteralInt n), rest)
        | none => throw (.typeError s!"Invalid integer literal: {tok}")
      else match parseSciNotation tok with
        | some n => return (mkStmtExprMd (.LiteralInt n), rest)
        | none => return (mkStmtExprMd (.Identifier tok), rest)

end SpecParser

/-- Parse a spec expression string into a Laurel StmtExprMd. -/
def parseSpecExpr (s : String) : Except TranslationError StmtExprMd := do
  let tokens := SpecParser.tokenize s
  let (expr, rest) ← SpecParser.parseExpr tokens
  if !rest.isEmpty then
    throw (.typeError s!"Unexpected tokens after spec expression: {rest}")
  return expr


end Strata.Solidity
