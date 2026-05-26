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

/-! ### UserDefinedTypeName (B2.2) -/

private def isUserDefinedTypeName (j : Json) (expectedName : String) : Bool :=
  match convertTypeName j with
  | .ok (type_name.UserDefinedTypeName _ name) => name.val == expectedName
  | _ => false

#guard isUserDefinedTypeName
  (jsonOf r#"{"nodeType":"UserDefinedTypeName","pathNode":{"nodeType":"IdentifierPath","name":"MyStruct"},"src":"50:8:0"}"#)
  "MyStruct"

#guard isUserDefinedTypeName
  (jsonOf r#"{"nodeType":"UserDefinedTypeName","pathNode":{"nodeType":"IdentifierPath","name":"IERC20"},"src":"50:6:0"}"#)
  "IERC20"

-- Missing pathNode is a structured error (matches solast.py's fatal exit).
private def errIsTypeName (j : Json) (pred : ConvertError → Bool) : Bool :=
  match convertTypeName j with
  | .error e => pred e
  | .ok _    => false

#guard errIsTypeName
  (jsonOf r#"{"nodeType":"UserDefinedTypeName","src":"50:8:0"}"#)
  (fun | .missingField "UserDefinedTypeName" "pathNode" => true | _ => false)

#guard errIsTypeName
  (jsonOf r#"{"nodeType":"UserDefinedTypeName","pathNode":{"nodeType":"IdentifierPath","name":""},"src":"50:0:0"}"#)
  (fun | .missingField "UserDefinedTypeName" "pathNode.name" => true | _ => false)

/-! ### ArrayTypeName (B2.2) -/

private def isArrayOfElementary (j : Json) (expectedBaseName : String) : Bool :=
  match convertTypeName j with
  | .ok (type_name.ArrayTypeName _ (type_name.ElementaryTypeName _ name _)) =>
    name.val == expectedBaseName
  | _ => false

#guard isArrayOfElementary
  (jsonOf r#"{"nodeType":"ArrayTypeName","baseType":{"nodeType":"ElementaryTypeName","name":"uint256","src":"60:7:0"},"src":"60:9:0"}"#)
  "uint256"

#guard errIsTypeName
  (jsonOf r#"{"nodeType":"ArrayTypeName","src":"60:0:0"}"#)
  (fun | .missingField "ArrayTypeName" "baseType" => true | _ => false)

/-! ### Mapping (B2.2) — note solc emits `nodeType: "Mapping"` -/

private def isAddressToUintMapping (j : Json) : Bool :=
  match convertTypeName j with
  | .ok (type_name.MappingType _
         (type_name.ElementaryTypeName _ k _)
         (type_name.ElementaryTypeName _ v _) _ _) =>
    k.val == "address" && v.val == "uint256"
  | _ => false

#guard isAddressToUintMapping (jsonOf r#"{
  "nodeType": "Mapping",
  "keyType": {"nodeType":"ElementaryTypeName","name":"address","src":"70:7:0"},
  "valueType": {"nodeType":"ElementaryTypeName","name":"uint256","src":"79:7:0"},
  "src": "62:25:0"
}"#)

-- Nested mappings: mapping(address => mapping(address => uint256))
private def isNestedMapping (j : Json) : Bool :=
  match convertTypeName j with
  | .ok (type_name.MappingType _
         (type_name.ElementaryTypeName _ k1 _)
         (type_name.MappingType _
           (type_name.ElementaryTypeName _ k2 _)
           (type_name.ElementaryTypeName _ v _) _ _) _ _) =>
    k1.val == "address" && k2.val == "address" && v.val == "uint256"
  | _ => false

#guard isNestedMapping (jsonOf r#"{
  "nodeType": "Mapping",
  "keyType": {"nodeType":"ElementaryTypeName","name":"address","src":"0:0:0"},
  "valueType": {
    "nodeType": "Mapping",
    "keyType": {"nodeType":"ElementaryTypeName","name":"address","src":"0:0:0"},
    "valueType": {"nodeType":"ElementaryTypeName","name":"uint256","src":"0:0:0"},
    "src": "0:0:0"
  },
  "src": "0:0:0"
}"#)

#guard errIsTypeName
  (jsonOf r#"{"nodeType":"Mapping","valueType":{"nodeType":"ElementaryTypeName","name":"uint256","src":"0:0:0"},"src":"0:0:0"}"#)
  (fun | .missingField "Mapping" "keyType" => true | _ => false)

#guard errIsTypeName
  (jsonOf r#"{"nodeType":"Mapping","keyType":{"nodeType":"ElementaryTypeName","name":"address","src":"0:0:0"},"src":"0:0:0"}"#)
  (fun | .missingField "Mapping" "valueType" => true | _ => false)

/-! ### Expressions (B2.3) -/

-- Helpers reused below for matching specific expression shapes.

private def idLit (j : Json) : Option String :=
  match convertNode j with
  | .ok (node.Identifier _ name) => some name.val
  | _ => none

private def litVal (j : Json) : Option (String × String) :=
  match convertNode j with
  | .ok (node.Literal _ v k) => some (v.val, k.val)
  | _ => none

/-- A simple `id` Identifier JSON. -/
private def idJ (name : String) : String :=
  "{\"nodeType\":\"Identifier\",\"name\":\"" ++ name ++ "\",\"src\":\"0:0:0\"}"

/-- A simple `<n>` number Literal JSON. -/
private def numJ (n : String) : String :=
  "{\"nodeType\":\"Literal\",\"value\":\"" ++ n ++ "\",\"kind\":\"number\",\"src\":\"0:0:0\"}"

/-- Wrap children inside a binary-op JSON shell. -/
private def binopJ (op lhs rhs : String) : String :=
  "{\"nodeType\":\"BinaryOperation\",\"leftExpression\":" ++ lhs ++
  ",\"rightExpression\":" ++ rhs ++
  ",\"operator\":\"" ++ op ++ "\",\"src\":\"0:0:0\"}"

private def unopJ (op pre sub : String) : String :=
  "{\"nodeType\":\"UnaryOperation\",\"subExpression\":" ++ sub ++
  ",\"operator\":\"" ++ op ++ "\",\"prefix\":" ++ pre ++ ",\"src\":\"0:0:0\"}"

private def assignJ (op lhs rhs : String) : String :=
  "{\"nodeType\":\"Assignment\",\"leftHandSide\":" ++ lhs ++
  ",\"rightHandSide\":" ++ rhs ++
  ",\"operator\":\"" ++ op ++ "\",\"src\":\"0:0:0\"}"

private def memJ (mem inner : String) : String :=
  "{\"nodeType\":\"MemberAccess\",\"expression\":" ++ inner ++
  ",\"memberName\":\"" ++ mem ++ "\",\"src\":\"0:0:0\"}"

private def idxJWith (base idx : String) : String :=
  "{\"nodeType\":\"IndexAccess\",\"baseExpression\":" ++ base ++
  ",\"indexExpression\":" ++ idx ++ ",\"src\":\"0:0:0\"}"

private def idxJBase (base : String) : String :=
  "{\"nodeType\":\"IndexAccess\",\"baseExpression\":" ++ base ++
  ",\"src\":\"0:0:0\"}"

private def fcJ (callee args : String) : String :=
  "{\"nodeType\":\"FunctionCall\",\"expression\":" ++ callee ++
  ",\"arguments\":" ++ args ++
  ",\"kind\":\"functionCall\",\"src\":\"0:0:0\"}"

private def fcoJ (inner : String) : String :=
  "{\"nodeType\":\"FunctionCallOptions\",\"expression\":" ++ inner ++
  ",\"src\":\"0:0:0\"}"

private def condJ (c t f : String) : String :=
  "{\"nodeType\":\"Conditional\",\"condition\":" ++ c ++
  ",\"trueExpression\":" ++ t ++
  ",\"falseExpression\":" ++ f ++ ",\"src\":\"0:0:0\"}"

private def tupleJ (comps : String) : String :=
  "{\"nodeType\":\"TupleExpression\",\"components\":" ++ comps ++
  ",\"src\":\"0:0:0\"}"

/-! #### BinaryOperation -/

private def isBinop (j : Json) (expectedOp : String)
    (lhsCheck : node SourceRange → Bool) (rhsCheck : node SourceRange → Bool) : Bool :=
  match convertNode j with
  | .ok (node.BinaryOperation _ l r op) =>
    op.val == expectedOp && lhsCheck l && rhsCheck r
  | _ => false

#guard isBinop (jsonOf (binopJ "+" (idJ "x") (numJ "1"))) "+"
  (fun | node.Identifier _ n => n.val == "x" | _ => false)
  (fun | node.Literal _ v _ => v.val == "1" | _ => false)

#guard isBinop (jsonOf (binopJ "==" (idJ "a") (idJ "b"))) "=="
  (fun | node.Identifier _ n => n.val == "a" | _ => false)
  (fun | node.Identifier _ n => n.val == "b" | _ => false)

/-! #### UnaryOperation — operator + prefix flag -/

private def isUnop (j : Json) (expectedOp expectedPrefix : String) : Bool :=
  match convertNode j with
  | .ok (node.UnaryOperation _ _ op pre) =>
    op.val == expectedOp && pre.val == expectedPrefix
  | _ => false

#guard isUnop (jsonOf (unopJ "!" "true" (idJ "x"))) "!" "true"
#guard isUnop (jsonOf (unopJ "++" "false" (idJ "x"))) "++" "false"

/-! #### Assignment -/

private def isAssign (j : Json) (expectedOp : String) : Bool :=
  match convertNode j with
  | .ok (node.Assignment _ _ _ op) => op.val == expectedOp
  | _ => false

#guard isAssign (jsonOf (assignJ "=" (idJ "x") (numJ "5"))) "="
#guard isAssign (jsonOf (assignJ "+=" (idJ "total") (numJ "1"))) "+="

/-! #### MemberAccess — `<expr>.member` -/

private def isMemberAccess (j : Json) (expectedMember : String)
    (innerCheck : node SourceRange → Bool) : Bool :=
  match convertNode j with
  | .ok (node.MemberAccess _ inner m) =>
    m.val == expectedMember && innerCheck inner
  | _ => false

#guard isMemberAccess (jsonOf (memJ "sender" (idJ "msg"))) "sender"
  (fun | node.Identifier _ n => n.val == "msg" | _ => false)

/-! #### IndexAccess — `<base>[<idx>]`, idx may be missing -/

private def isIndexAccessOf (j : Json) (expectedBase : String) (hasIdx : Bool) : Bool :=
  match convertNode j with
  | .ok (node.IndexAccess _ (node.Identifier _ b) idx) =>
    b.val == expectedBase &&
    (match idx with
     | Strata.Solidity.opt_node.some_node _ _ => hasIdx
     | Strata.Solidity.opt_node.missing_node _ => !hasIdx)
  | _ => false

#guard isIndexAccessOf (jsonOf (idxJWith (idJ "balances") (idJ "user"))) "balances" true
#guard isIndexAccessOf (jsonOf (idxJBase (idJ "arr"))) "arr" false

/-! #### FunctionCall — callee + args, kind, names -/

private def fcArgCount (j : Json) : Nat :=
  match convertNode j with
  | .ok (node.FunctionCall _ _ args _ _) => args.val.size
  | _ => 999  -- Sentinel: doesn't match any expected count, so #guard fails on error.

#guard fcArgCount (jsonOf (fcJ (idJ "transfer") ("[" ++ idJ "to" ++ "," ++ numJ "100" ++ "]"))) == 2
#guard fcArgCount (jsonOf (fcJ (idJ "f") "[]")) == 0

-- FunctionCallOptions wrapper strips itself and recurses on `expression`.
#guard idLit (jsonOf (fcoJ (idJ "addr"))) == some "addr"

/-! #### Conditional — `c ? t : f` -/

private def isCondId3 (j : Json) (cName tName fName : String) : Bool :=
  match convertNode j with
  | .ok (node.Conditional _
         (node.Identifier _ c)
         (node.Identifier _ t)
         (node.Identifier _ f)) =>
    c.val == cName && t.val == tName && f.val == fName
  | _ => false

#guard isCondId3 (jsonOf (condJ (idJ "ok") (idJ "a") (idJ "b"))) "ok" "a" "b"

/-! #### TupleExpression — null components are dropped -/

private def tupleSize (j : Json) : Nat :=
  match convertNode j with
  | .ok (node.TupleExpression _ comps) => comps.val.size
  | _ => 999

-- (a, b) → 2 components
#guard tupleSize (jsonOf (tupleJ ("[" ++ idJ "a" ++ "," ++ idJ "b" ++ "]"))) == 2

-- (a, ) → null trailing component is dropped
#guard tupleSize (jsonOf (tupleJ ("[" ++ idJ "a" ++ ",null]"))) == 1

-- () → zero components
#guard tupleSize (jsonOf (tupleJ "[]")) == 0

/-! #### ElementaryTypeNameExpression — `address(0)`-style conversions -/

private def isEtne (j : Json) (expectedName : String) : Bool :=
  match convertNode j with
  | .ok (node.ElementaryTypeNameExpression _ tn) => tn.val == expectedName
  | _ => false

#guard isEtne
  (jsonOf r#"{"nodeType":"ElementaryTypeNameExpression","typeName":{"name":"address","nodeType":"ElementaryTypeName"},"src":"0:0:0"}"#)
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
