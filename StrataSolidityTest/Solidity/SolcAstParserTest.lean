/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

import StrataSolidity.SolcAstParser

/-!
# Unit tests for the solc-AST → Lean ADT translators (Group B step 2)

These tests exercise the per-`nodeType` translators in
`StrataSolidity.SolcAstParser` against hand-crafted JSON fragments.
The goal is fast feedback for individual node-shape regressions —
the end-to-end fixture round-trip lives in B2.6.

Tests use `#guard` so failures show up at `lake build` time.

This file (B2.1) covers the three leaf nodes — the ones with no
recursive children:
  * `Identifier`        →  `node.Identifier`
  * `Literal`           →  `node.Literal`
  * `ElementaryTypeName`→  `type_name.ElementaryTypeName`
-/

open Lean (Json)
open Strata (SourceRange)
open Strata.Solidity (node type_name)
open Strata.Solidity.SolcAst

namespace SolcAstParserTest.B2_1

private def jsonOf (s : String) : Json :=
  match Json.parse s with
  | .ok j  => j
  | .error _ => Json.null

/-! ### Identifier -/

private def isIdentifier (j : Json) (expectedName : String) : Bool :=
  match convertNode j with
  | .ok (node.Identifier _ name) => name.val == expectedName
  | _ => false

#guard isIdentifier (jsonOf r#"{"nodeType":"Identifier","name":"x","src":"10:1:0"}"#) "x"

#guard isIdentifier (jsonOf r#"{"nodeType":"Identifier","name":"balances","src":"40:8:0"}"#) "balances"

-- Missing `name` defaults to "" (matches solast.py:_str behaviour).
#guard isIdentifier (jsonOf r#"{"nodeType":"Identifier","src":"10:1:0"}"#) ""

/-! ### Literal -/

private def isLiteral (j : Json) (expectedVal expectedKind : String) : Bool :=
  match convertNode j with
  | .ok (node.Literal _ val kind _sub) => val.val == expectedVal && kind.val == expectedKind
  | _ => false

#guard isLiteral
  (jsonOf r#"{"nodeType":"Literal","value":"42","kind":"number","src":"20:2:0"}"#)
  "42" "number"

#guard isLiteral
  (jsonOf r#"{"nodeType":"Literal","value":"true","kind":"bool","src":"20:4:0"}"#)
  "true" "bool"

#guard isLiteral
  (jsonOf r#"{"nodeType":"Literal","value":"hello","kind":"string","src":"20:5:0"}"#)
  "hello" "string"

-- Missing `kind` defaults to "number" (matches solast.py).
#guard isLiteral
  (jsonOf r#"{"nodeType":"Literal","value":"99","src":"30:2:0"}"#)
  "99" "number"

-- Missing `value` defaults to "".
#guard isLiteral
  (jsonOf r#"{"nodeType":"Literal","kind":"number","src":"30:0:0"}"#)
  "" "number"

/-! ### ElementaryTypeName -/

private def isElementaryTypeName (j : Json) (expectedName : String) : Bool :=
  match convertTypeName j with
  | .ok (type_name.ElementaryTypeName _ name _mut) => name.val == expectedName
  | _ => false

#guard isElementaryTypeName
  (jsonOf r#"{"nodeType":"ElementaryTypeName","name":"uint256","src":"30:7:0"}"#)
  "uint256"

#guard isElementaryTypeName
  (jsonOf r#"{"nodeType":"ElementaryTypeName","name":"bool","src":"30:4:0"}"#)
  "bool"

#guard isElementaryTypeName
  (jsonOf r#"{"nodeType":"ElementaryTypeName","name":"address","src":"30:7:0"}"#)
  "address"

/-! ### Source range parsing — start and stop offsets -/

private def srcRangeOk (j : Json) (expStart expStop : Nat) : Bool :=
  match convertNode j with
  | .ok (node.Identifier sr _) =>
    sr.start.byteIdx == expStart && sr.stop.byteIdx == expStop
  | _ => false

#guard srcRangeOk (jsonOf r#"{"nodeType":"Identifier","name":"y","src":"10:5:0"}"#) 10 15
#guard srcRangeOk (jsonOf r#"{"nodeType":"Identifier","name":"y","src":"100:0:0"}"#) 100 100

/-! ### Error paths -/

private def errIs (j : Json) (pred : ConvertError → Bool) : Bool :=
  match convertNode j with
  | .error e => pred e
  | .ok _    => false

#guard errIs
  (jsonOf r#"{"nodeType":"NotARealNodeType","src":"0:0:0"}"#)
  (fun | .unknownNodeType "NotARealNodeType" => true | _ => false)

#guard errIs
  (jsonOf r#"{"src":"0:0:0"}"#)
  (fun | .missingNodeType => true | _ => false)

end SolcAstParserTest.B2_1
