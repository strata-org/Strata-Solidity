/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/
module

public import StrataDDM.AST

/-!
# Spec annotation parser — DDM grammar (scaffold)

This is the **target** for the spec-parser-via-DDM migration. When complete,
it will replace the ~250-line hand-rolled recursive-descent parser inside
`StrataSolidity/SolTranslator/SpecParser.lean` (specifically `tokenize` and
`parseExpr` and their helpers).

## Status: SCAFFOLD

The current `SpecParser.lean` is unchanged. This file holds the future DDM
grammar and a migration plan.

## Two-layer architecture (only Layer 2 changes)

Spec annotations use a syntax that's *not* native Solidity (it has keywords
like `requires`, `ensures`, `modifies`, `forall`, `exists`, `old`, `==>`).
We parse them in two layers, and only the second layer becomes DDM.

### Layer 1 — line-level keyword dispatch (stays as Lean code)

`parseStrataAnnotations` walks the NatSpec doc string line by line,
finds lines that start with `@custom:strata ` (or `* @custom:strata ` for
the `/** … */` multi-line form), and discriminates on the first keyword:

  `requires` | `ensures` | `invariant` | `modifies` | `loop-invariant`

Each match becomes a `StrataAnnotation` variant carrying the keyword tag
and the rest of the line as a raw `String`. **This stays as plain Lean
code in `SpecParser.lean`.** It's trivial pattern matching (not a parsing
problem) and the line-orientation is fixed by NatSpec's structure, which
solc has already extracted for us.

### Layer 2 — expression grammar (replaced by DDM)

The raw string after the keyword is then parsed as an expression. **This
is what the DDM grammar below replaces.** The expression grammar includes
constructs that are *not* native Solidity:

  - `forall v : T :: body`           — universal quantifier
  - `exists v : T :: body`           — existential quantifier
  - `old(expr)`                      — pre-state reference
  - `==>`                            — implication

…on top of the usual Solidity-flavored arithmetic, comparison, boolean,
member access, and index access.

## Grammar to express

  expr        ::= or_expr
  or_expr     ::= and_expr ("||" and_expr)*
  and_expr    ::= impl_expr ("&&" impl_expr)*
  impl_expr   ::= cmp_expr ("==>" cmp_expr)*
  cmp_expr    ::= add_expr (("=="|"!="|"<"|"<="|">"|">=") add_expr)?
  add_expr    ::= mul_expr (("+"|"-") mul_expr)*
  mul_expr    ::= unary    (("*"|"/"|"%") unary)*
  unary       ::= ("!" | "-")? postfix
  postfix     ::= atom (("." Ident) | ("[" expr "]") | ("(" args ")"))*
  atom        ::= "true" | "false"
                | Number
                | "old" "(" expr ")"
                | "address" "(" expr ")"
                | "msg" "." ("sender" | "value")
                | "type" "(" Ident ")" "." ("min" | "max")
                | "forall" Ident ":" Ident "::" expr
                | "exists" Ident ":" Ident "::" expr
                | "(" expr ")"
                | Ident

The output type is `StmtExprMd` (Laurel AST), produced via the helpers in
`StrataSolidity/SolTranslator/Types.lean` (`mkIdentifier`, `mkFieldSelect`,
`mkForall`, `mkExists`, etc.).

## DDM approach

Strata's DDM (Dialect Definition Mechanism) lets us specify the grammar
declaratively via `#dialect ... #strata_gen <Name>`. See
`Strata/Languages/Python/Specs/DDM.lean` for a similar AST-only spec language
(PythonSpecs has expression literals, type names, and similar constructs to
ours).

Sketch (to be fleshed out):

```
#dialect
dialect StrataSpec;

category Expr;

// Atoms
op exprTrue () : Expr => "true";
op exprFalse () : Expr => "false";
op exprNum (n : Num) : Expr => n;
op exprIdent (x : Ident) : Expr => x;

// Member / index
op exprField (e : Expr, x : Ident) : Expr => e "." x;
op exprIndex (e : Expr, i : Expr) : Expr => e "[" i "]";
op exprCall (e : Expr, args : CommaSepBy Expr) : Expr => e "(" args ")";

// Old marker
op exprOld (inner : Expr) : Expr => "old" "(" inner ")";

// Quantifiers (the awkward `Ident : Ident :: body` shape)
op exprForall (v : Ident, t : Ident, body : Expr) : Expr =>
  "forall" v ":" t "::" body;
op exprExists (v : Ident, t : Ident, body : Expr) : Expr =>
  "exists" v ":" t "::" body;

// Operators with precedence — DDM supports left-assoc precedence climbing
// via op_left / op_prefix (see Core grammar).
op_left "||" 10 boolOr  (Expr, Expr) : Expr;
op_left "&&" 20 boolAnd (Expr, Expr) : Expr;
op_left "==>" 25 implies (Expr, Expr) : Expr;
op       "==" 30 eq      (Expr, Expr) : Expr;
op       "!=" 30 neq     (Expr, Expr) : Expr;
op       "<"  30 lt      (Expr, Expr) : Expr;
// ... etc for <=, >, >=
op_left "+"  40 add     (Expr, Expr) : Expr;
op_left "-"  40 sub     (Expr, Expr) : Expr;
op_left "*"  50 mul     (Expr, Expr) : Expr;
op_left "/"  50 div     (Expr, Expr) : Expr;
op_left "%"  50 mod     (Expr, Expr) : Expr;
op_prefix "!" 60 not    (Expr)        : Expr;
op_prefix "-" 60 neg    (Expr)        : Expr;
```

## Migration plan

1. Land this skeleton; verify it parses a few representative spec strings via
   `Strata.parseProgram` (or the equivalent for inline-text inputs).
2. Write a small `lower : StrataSpec.Expr → StmtExprMd` converter that calls
   `mkIdentifier` / `mkFieldSelect` / `mkForall` / `mkExists` / etc.
3. Replace `StrataSolidity.parseSpecExpr` (the **expression-level** entry
   point) with a thin wrapper that invokes the DDM parser then runs `lower`.
   `parseStrataAnnotations` (the **line-level** keyword dispatcher) stays
   unchanged.
4. Delete `SpecParser.tokenize` and `SpecParser.parseExpr` plus their
   helpers (~250 lines of hand-rolled recursive descent). Keep the
   `StrataAnnotation` inductive and `parseStrataAnnotations`.
5. Verify all golden tests still pass with the new parser.

## Why it's worth it

- ~250 lines of hand-rolled tokenizer/parser disappear.
- Source positions become precise (token-level), improving SARIF accuracy
  for spec syntax errors.
- Adding a new spec primitive (e.g., `decreases`) is a grammar edit, not a
  recursive-descent surgery.
- Aligns with how Laurel itself is parsed — same mental model across the
  pipeline.

## Why it's awkward

- The grammar is embedded in NatSpec comments. The lexer first extracts
  one-line strings via `parseStrataAnnotations`; only then does the spec
  expression parser run. DDM expects to consume a stream directly. Probably
  workable: feed each extracted string to `Strata.parseInput` separately.
- We just rewrote this parser for the upstream port. Doing another structural
  rewrite right after feels disruptive — best to land Group A first, when
  most of the surrounding code is already Lean-native.
-/

public section
namespace Strata.Solidity.SpecGrammar

-- TODO(spec-ddm-parser): inline `#dialect ... #strata_gen StrataSpec` here,
-- following the sketch above. See Strata/Languages/Python/Specs/DDM.lean for
-- a complete worked example with similar surface syntax.

end Strata.Solidity.SpecGrammar
end
