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
open StrataDDM (SourceRange)
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

private def isArrayOfElementary (j : Json) (expectedBaseName : String)
    (expectedLength : String := "") : Bool :=
  match convertTypeName j with
  | .ok (type_name.ArrayTypeName _ (type_name.ElementaryTypeName _ name _) length) =>
    name.val == expectedBaseName && length.val == expectedLength
  | _ => false

#guard isArrayOfElementary
  (jsonOf r#"{"nodeType":"ArrayTypeName","baseType":{"nodeType":"ElementaryTypeName","name":"uint256","src":"60:7:0"},"src":"60:9:0"}"#)
  "uint256"

-- A fixed-size array's length, from the type string (`N` evaluated).
#guard isArrayOfElementary
  (jsonOf r#"{"nodeType":"ArrayTypeName","baseType":{"nodeType":"ElementaryTypeName","name":"uint256","src":"60:7:0"},"length":{"nodeType":"Identifier","name":"N","src":"68:1:0"},"typeDescriptions":{"typeString":"uint256[3]"},"src":"60:10:0"}"#)
  "uint256" "3"
#guard isArrayOfElementary
  (jsonOf r#"{"nodeType":"ArrayTypeName","baseType":{"nodeType":"ElementaryTypeName","name":"uint256","src":"60:7:0"},"typeDescriptions":{"typeString":"uint256[] storage ref"},"src":"60:9:0"}"#)
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
  | .ok (node.Literal _ v k _sub) => some (v.val, k.val)
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
  (fun | node.Literal _ v _ _ => v.val == "1" | _ => false)

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

/-! ### Statements (B2.4) -/

/-- JSON builders for statement fixtures. -/
private def blockJ (statements : String) : String :=
  "{\"nodeType\":\"Block\",\"statements\":" ++ statements ++ ",\"src\":\"0:0:0\"}"

private def uncheckedBlockJ (statements : String) : String :=
  "{\"nodeType\":\"UncheckedBlock\",\"statements\":" ++ statements ++ ",\"src\":\"0:0:0\"}"

private def exprStmtJ (e : String) : String :=
  "{\"nodeType\":\"ExpressionStatement\",\"expression\":" ++ e ++ ",\"src\":\"0:0:0\"}"

private def returnJBare : String :=
  "{\"nodeType\":\"Return\",\"src\":\"0:0:0\"}"

private def returnJWith (e : String) : String :=
  "{\"nodeType\":\"Return\",\"expression\":" ++ e ++ ",\"src\":\"0:0:0\"}"

private def ifStmtJ (cond t : String) : String :=
  "{\"nodeType\":\"IfStatement\",\"condition\":" ++ cond ++
  ",\"trueBody\":" ++ t ++ ",\"src\":\"0:0:0\"}"

private def ifElseJ (cond t f : String) : String :=
  "{\"nodeType\":\"IfStatement\",\"condition\":" ++ cond ++
  ",\"trueBody\":" ++ t ++ ",\"falseBody\":" ++ f ++ ",\"src\":\"0:0:0\"}"

private def whileJ (cond body : String) : String :=
  "{\"nodeType\":\"WhileStatement\",\"condition\":" ++ cond ++
  ",\"body\":" ++ body ++ ",\"src\":\"0:0:0\"}"

private def forJBare (body : String) : String :=
  "{\"nodeType\":\"ForStatement\",\"body\":" ++ body ++ ",\"src\":\"0:0:0\"}"

private def vdsJ (decls init : String) : String :=
  "{\"nodeType\":\"VariableDeclarationStatement\",\"declarations\":" ++ decls ++
  ",\"initialValue\":" ++ init ++ ",\"src\":\"0:0:0\"}"

private def placeholderJ : String :=
  "{\"nodeType\":\"PlaceholderStatement\",\"src\":\"0:0:0\"}"

/-! #### Block / UncheckedBlock — sequence of statements -/

private def blockSize (j : Json) : Nat :=
  match convertNode j with
  | .ok (node.Block _ stmts) => stmts.val.size
  | _ => 999

private def uncheckedBlockSize (j : Json) : Nat :=
  match convertNode j with
  | .ok (node.UncheckedBlock _ stmts) => stmts.val.size
  | _ => 999

#guard blockSize (jsonOf (blockJ "[]")) == 0
#guard blockSize (jsonOf (blockJ ("[" ++ exprStmtJ (idJ "x") ++ "]"))) == 1
#guard blockSize
  (jsonOf (blockJ ("[" ++ exprStmtJ (idJ "x") ++ "," ++ exprStmtJ (idJ "y") ++ "]")))
  == 2

#guard uncheckedBlockSize (jsonOf (uncheckedBlockJ "[]")) == 0
#guard uncheckedBlockSize (jsonOf (uncheckedBlockJ ("[" ++ exprStmtJ (idJ "x") ++ "]"))) == 1

/-! #### ExpressionStatement -/

private def isExprStmtId (j : Json) (expectedName : String) : Bool :=
  match convertNode j with
  | .ok (node.ExpressionStatement _ (node.Identifier _ n)) => n.val == expectedName
  | _ => false

#guard isExprStmtId (jsonOf (exprStmtJ (idJ "x"))) "x"

/-! #### Return -/

private def isBareReturn (j : Json) : Bool :=
  match convertNode j with
  | .ok (node.Return _ (Strata.Solidity.opt_node.missing_node _)) => true
  | _ => false

private def isReturnIdent (j : Json) (expected : String) : Bool :=
  match convertNode j with
  | .ok (node.Return _ (Strata.Solidity.opt_node.some_node _ (node.Identifier _ n))) =>
    n.val == expected
  | _ => false

#guard isBareReturn (jsonOf returnJBare)
#guard isReturnIdent (jsonOf (returnJWith (idJ "x"))) "x"

/-! #### IfStatement — true body required, false body optional -/

private def isIfWithoutElse (j : Json) : Bool :=
  match convertNode j with
  | .ok (node.IfStatement _ _ _ (Strata.Solidity.opt_node.missing_node _)) => true
  | _ => false

private def isIfWithElse (j : Json) : Bool :=
  match convertNode j with
  | .ok (node.IfStatement _ _ _ (Strata.Solidity.opt_node.some_node _ _)) => true
  | _ => false

#guard isIfWithoutElse (jsonOf (ifStmtJ (idJ "ok") (blockJ "[]")))
#guard isIfWithElse (jsonOf (ifElseJ (idJ "ok") (blockJ "[]") (blockJ "[]")))

/-! #### WhileStatement -/

private def isWhileWithBlockBody (j : Json) : Bool :=
  match convertNode j with
  | .ok (node.WhileStatement _ _ (node.Block _ _)) => true
  | _ => false

#guard isWhileWithBlockBody (jsonOf (whileJ (idJ "cond") (blockJ "[]")))

/-! #### ForStatement — `for(;;)` has all three init/cond/loop optional -/

private def forAllMissing (j : Json) : Bool :=
  match convertNode j with
  | .ok (node.ForStatement _
         (Strata.Solidity.opt_node.missing_node _)
         (Strata.Solidity.opt_node.missing_node _)
         (Strata.Solidity.opt_node.missing_node _)
         (node.Block _ _)) => true
  | _ => false

#guard forAllMissing (jsonOf (forJBare (blockJ "[]")))

/-! #### VariableDeclarationStatement — declarations + optional init,
     supports tuple destructuring with null slots -/

private def vdsSize (j : Json) : Nat :=
  match convertNode j with
  | .ok (node.VariableDeclarationStatement _ decls _) => decls.val.size
  | _ => 999

private def vdsHasInit (j : Json) : Bool :=
  match convertNode j with
  | .ok (node.VariableDeclarationStatement _ _ (Strata.Solidity.opt_node.some_node _ _)) => true
  | _ => false

private def vdsMissingInit (j : Json) : Bool :=
  match convertNode j with
  | .ok (node.VariableDeclarationStatement _ _ (Strata.Solidity.opt_node.missing_node _)) => true
  | _ => false

-- Single declaration with init: `uint x = 5;` (we use Identifier as a stand-in
-- since VariableDeclaration itself isn't translated until B2.5).
#guard vdsHasInit (jsonOf (vdsJ ("[" ++ idJ "decl1" ++ "]") (numJ "5")))
#guard vdsSize   (jsonOf (vdsJ ("[" ++ idJ "decl1" ++ "]") (numJ "5"))) == 1

-- Tuple destructuring with a null slot: `(uint a, , bool c) = …` → 3 decls
-- (well, here we use Identifier placeholders for the non-null slots).
#guard vdsSize (jsonOf (vdsJ ("[" ++ idJ "a" ++ ",null," ++ idJ "c" ++ "]") (idJ "f"))) == 3

-- No initializer: `uint x;`
#guard vdsMissingInit
  (jsonOf "{\"nodeType\":\"VariableDeclarationStatement\",\"declarations\":[],\"src\":\"0:0:0\"}")

/-! #### PlaceholderStatement — `_;` lowered to ExpressionStatement(Literal "_") -/

private def isPlaceholderLit (j : Json) : Bool :=
  match convertNode j with
  | .ok (node.ExpressionStatement _ (node.Literal _ v k _)) =>
    v.val == "_" && k.val == "string"
  | _ => false

#guard isPlaceholderLit (jsonOf placeholderJ)

/-! ### Declarations (B2.5) -/

/-- JSON builders for declaration fixtures. -/
private def pragmaJ (literals : String) : String :=
  "{\"nodeType\":\"PragmaDirective\",\"literals\":" ++ literals ++ ",\"src\":\"0:0:0\"}"

private def contractJ (name kind nodes baseContracts : String) : String :=
  "{\"nodeType\":\"ContractDefinition\",\"name\":\"" ++ name ++
  "\",\"contractKind\":\"" ++ kind ++
  "\",\"nodes\":" ++ nodes ++
  ",\"baseContracts\":" ++ baseContracts ++
  ",\"src\":\"0:0:0\"}"

private def baseContractJ (name : String) : String :=
  "{\"baseName\":{\"name\":\"" ++ name ++ "\"}}"

private def parameterListJ (params : String) : String :=
  "{\"nodeType\":\"ParameterList\",\"parameters\":" ++ params ++ ",\"src\":\"0:0:0\"}"

private def varDeclJ (name typeName : String) : String :=
  "{\"nodeType\":\"VariableDeclaration\",\"name\":\"" ++ name ++
  "\",\"typeName\":" ++ typeName ++
  ",\"stateVariable\":false,\"constant\":false,\"storageLocation\":\"default\"" ++
  ",\"src\":\"0:0:0\"}"

private def funcDefJ (name kind vis params returnParams body modifiers : String) : String :=
  "{\"nodeType\":\"FunctionDefinition\",\"name\":\"" ++ name ++
  "\",\"kind\":\"" ++ kind ++
  "\",\"stateMutability\":\"nonpayable\",\"visibility\":\"" ++ vis ++
  "\",\"parameters\":" ++ params ++
  ",\"returnParameters\":" ++ returnParams ++
  ",\"body\":" ++ body ++
  ",\"modifiers\":" ++ modifiers ++
  ",\"src\":\"0:0:0\"}"

private def modDefJ (name params body : String) : String :=
  "{\"nodeType\":\"ModifierDefinition\",\"name\":\"" ++ name ++
  "\",\"parameters\":" ++ params ++
  ",\"body\":" ++ body ++
  ",\"src\":\"0:0:0\"}"

private def modInvJ (name args : String) : String :=
  "{\"nodeType\":\"ModifierInvocation\",\"modifierName\":{\"name\":\"" ++ name ++
  "\"},\"arguments\":" ++ args ++ ",\"src\":\"0:0:0\"}"

private def structDefJ (name members : String) : String :=
  "{\"nodeType\":\"StructDefinition\",\"name\":\"" ++ name ++
  "\",\"members\":" ++ members ++ ",\"src\":\"0:0:0\"}"

private def enumDefJ (name members : String) : String :=
  "{\"nodeType\":\"EnumDefinition\",\"name\":\"" ++ name ++
  "\",\"members\":" ++ members ++ ",\"src\":\"0:0:0\"}"

private def enumValueJ (name : String) : String :=
  "{\"nodeType\":\"EnumValue\",\"name\":\"" ++ name ++ "\",\"src\":\"0:0:0\"}"

private def elementaryTNJ (name : String) : String :=
  "{\"nodeType\":\"ElementaryTypeName\",\"name\":\"" ++ name ++ "\",\"src\":\"0:0:0\"}"

/-! #### PragmaDirective -/

private def pragmaLits (j : Json) : Option (Array String) :=
  match convertNode j with
  | .ok (node.PragmaDirective _ lits) => some (lits.val.map (·.val))
  | _ => none

#guard pragmaLits (jsonOf (pragmaJ "[\"solidity\",\"^\",\"0.8\",\".0\"]"))
  == some #["solidity", "^", "0.8", ".0"]

#guard pragmaLits (jsonOf (pragmaJ "[]")) == some #[]

/-! #### ContractDefinition -/

private def contractInfo (j : Json) : Option (String × String × Nat × Array String) :=
  match convertNode j with
  | .ok (node.ContractDefinition _ name kind _abstract members _doc bases) =>
    some (name.val, kind.val, members.val.size, bases.val.map (·.val))
  | _ => none

#guard contractInfo (jsonOf (contractJ "Token" "contract" "[]" "[]"))
  == some ("Token", "contract", 0, #[])

#guard contractInfo (jsonOf (contractJ "IMyInterface" "interface" "[]" "[]"))
  == some ("IMyInterface", "interface", 0, #[])

#guard contractInfo
  (jsonOf (contractJ "Child" "contract" "[]"
    ("[" ++ baseContractJ "Parent1" ++ "," ++ baseContractJ "Parent2" ++ "]")))
  == some ("Child", "contract", 0, #["Parent1", "Parent2"])

-- Contract members count should drop StructuredDocumentation/Events/Imports.
-- Use an EnumValue (a real, simple node) plus a noise node to verify skip.
private def docNoiseJ : String :=
  "{\"nodeType\":\"StructuredDocumentation\",\"text\":\"docs\",\"src\":\"0:0:0\"}"

#guard contractInfo
  (jsonOf (contractJ "C" "contract"
    ("[" ++ enumValueJ "A" ++ "," ++ docNoiseJ ++ "," ++ enumValueJ "B" ++ "]")
    "[]"))
  == some ("C", "contract", 2, #[])

/-! #### ParameterList -/

private def paramListSize (j : Json) : Nat :=
  match convertNode j with
  | .ok (node.ParameterList _ params) => params.val.size
  | _ => 999

#guard paramListSize (jsonOf (parameterListJ "[]")) == 0
#guard paramListSize
  (jsonOf (parameterListJ ("[" ++ varDeclJ "x" (elementaryTNJ "uint256") ++ "]")))
  == 1
#guard paramListSize
  (jsonOf (parameterListJ
    ("[" ++ varDeclJ "x" (elementaryTNJ "uint256") ++
     "," ++ varDeclJ "y" (elementaryTNJ "bool") ++ "]")))
  == 2

/-! #### VariableDeclaration -/

private def varDeclInfo (j : Json) : Option (String × String × String × String) :=
  match convertNode j with
  | .ok (node.VariableDeclaration _ name typeName stateVar const? _ _ _ _ _ _) =>
    let typeStr := match typeName with
      | Strata.Solidity.opt_type_name.some_type_name _
          (type_name.ElementaryTypeName _ n _) => n.val
      | _ => "<other>"
    some (name.val, typeStr, stateVar.val, const?.val)
  | _ => none

#guard varDeclInfo (jsonOf (varDeclJ "x" (elementaryTNJ "uint256")))
  == some ("x", "uint256", "false", "false")

#guard varDeclInfo (jsonOf (varDeclJ "owner" (elementaryTNJ "address")))
  == some ("owner", "address", "false", "false")

-- Test missing typeName → opt_type_name.missing_type_name
private def varDeclMissingType (j : Json) : Bool :=
  match convertNode j with
  | .ok (node.VariableDeclaration _ _ (Strata.Solidity.opt_type_name.missing_type_name _) _ _ _ _ _ _ _ _) => true
  | _ => false

#guard varDeclMissingType
  (jsonOf "{\"nodeType\":\"VariableDeclaration\",\"name\":\"x\",\"stateVariable\":false,\"constant\":false,\"storageLocation\":\"default\",\"src\":\"0:0:0\"}")

/-! #### ModifierDefinition + ModifierInvocation -/

private def modDefInfo (j : Json) : Option (String × Bool) :=
  match convertNode j with
  | .ok (node.ModifierDefinition _ name _params body) =>
    let hasBody := match body with
      | Strata.Solidity.opt_node.some_node _ _ => true
      | Strata.Solidity.opt_node.missing_node _ => false
    some (name.val, hasBody)
  | _ => none

#guard modDefInfo
  (jsonOf (modDefJ "onlyOwner" (parameterListJ "[]") (blockJ "[]")))
  == some ("onlyOwner", true)

private def modInvName (j : Json) : Option String :=
  match convertNode j with
  | .ok (node.ModifierInvocation _ name _) => some name.val
  | _ => none

#guard modInvName (jsonOf (modInvJ "onlyOwner" "[]")) == some "onlyOwner"

/-! #### FunctionDefinition -/

private def funcDefSig (j : Json) : Option (String × String × String × Bool × Nat) :=
  match convertNode j with
  | .ok (node.FunctionDefinition _ name kind _stateMut vis _virtual _params _returnParams body _doc mods) =>
    let hasBody := match body with
      | Strata.Solidity.opt_node.some_node _ _ => true
      | Strata.Solidity.opt_node.missing_node _ => false
    some (name.val, kind.val, vis.val, hasBody, mods.val.size)
  | _ => none

#guard funcDefSig
  (jsonOf (funcDefJ "transfer" "function" "external"
    (parameterListJ ("[" ++ varDeclJ "to" (elementaryTNJ "address") ++ "]"))
    (parameterListJ "[]") (blockJ "[]") "[]"))
  == some ("transfer", "function", "external", true, 0)

-- Constructor with one modifier
#guard funcDefSig
  (jsonOf (funcDefJ "" "constructor" "public"
    (parameterListJ "[]") (parameterListJ "[]")
    (blockJ "[]")
    ("[" ++ modInvJ "onlyOwner" "[]" ++ "]")))
  == some ("", "constructor", "public", true, 1)

/-! #### StructDefinition / EnumDefinition / EnumValue -/

private def structInfo (j : Json) : Option (String × Nat) :=
  match convertNode j with
  | .ok (node.StructDefinition _ name members) => some (name.val, members.val.size)
  | _ => none

#guard structInfo
  (jsonOf (structDefJ "S"
    ("[" ++ varDeclJ "a" (elementaryTNJ "uint256") ++ "," ++
            varDeclJ "b" (elementaryTNJ "bool") ++ "]")))
  == some ("S", 2)

private def enumInfo (j : Json) : Option (String × Nat) :=
  match convertNode j with
  | .ok (node.EnumDefinition _ name members) => some (name.val, members.val.size)
  | _ => none

#guard enumInfo
  (jsonOf (enumDefJ "Status"
    ("[" ++ enumValueJ "Pending" ++ "," ++ enumValueJ "Active" ++ "," ++
            enumValueJ "Closed" ++ "]")))
  == some ("Status", 3)

private def enumValueName (j : Json) : Option String :=
  match convertNode j with
  | .ok (node.EnumValue _ n) => some n.val
  | _ => none

#guard enumValueName (jsonOf (enumValueJ "Pending")) == some "Pending"

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

/-! #### `$` identifiers are renamed for Laurel -/
#guard mangleName "$" == "strata$dollar$"
#guard mangleName "$total" == "strata$dollar$total"
#guard mangleName "a$b" == "a$b"
#guard unmangleName (mangleName "$total") == "$total"

