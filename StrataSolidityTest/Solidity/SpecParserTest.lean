/-
  Unit tests for the Strata Solidity spec expression parser.
-/
import StrataSolidity.SolTranslator.SpecParser
import StrataSolidity.SolTranslator.Types

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
