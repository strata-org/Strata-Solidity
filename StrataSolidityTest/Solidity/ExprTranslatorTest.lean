/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

/-
  Unit tests for helpers of the Solidity statement and expression translator.
-/
import StrataSolidity.SolTranslator.ExprTranslator

namespace Strata.Solidity.ExprTranslator.Tests

open Strata.Solidity

/-! ## What inline assembly may do -/

/-- The shape of solc's Yul AST (`InlineAssembly.AST`), `src` omitted. -/
private def yulBlock : String := "{\"nodeType\":\"YulBlock\",\"statements\":[
  {\"nodeType\":\"YulAssignment\",\"variableNames\":[{\"name\":\"t\",\"nodeType\":\"YulIdentifier\"}],
   \"value\":{\"nodeType\":\"YulFunctionCall\",\"functionName\":{\"name\":\"sload\",\"nodeType\":\"YulIdentifier\"},
     \"arguments\":[{\"name\":\"a\",\"nodeType\":\"YulIdentifier\"}]}},
  {\"nodeType\":\"YulVariableDeclaration\",\"variables\":[{\"name\":\"tmp\",\"nodeType\":\"YulTypedName\"}]},
  {\"nodeType\":\"YulFunctionDefinition\",\"name\":\"f\",\"body\":{\"nodeType\":\"YulBlock\",\"statements\":[
    {\"nodeType\":\"YulAssignment\",\"variableNames\":[{\"name\":\"q\",\"nodeType\":\"YulIdentifier\"}]}]}},
  {\"nodeType\":\"YulAssignment\",\"variableNames\":[{\"name\":\"p.slot\",\"nodeType\":\"YulIdentifier\"},
    {\"name\":\"u\",\"nodeType\":\"YulIdentifier\"}]}]}"

/-- A block calling `fn`. -/
private def calling (fn : String) : String :=
  "{\"nodeType\":\"YulBlock\",\"statements\":[{\"nodeType\":\"YulExpressionStatement\",
    \"expression\":{\"nodeType\":\"YulFunctionCall\",\"functionName\":{\"name\":\"" ++ fn ++
    "\",\"nodeType\":\"YulIdentifier\"},\"arguments\":[]}}]}"

private def summary? (payload : String) : Option (List String × Bool × Bool × Bool) :=
  (yulSummary? payload).map fun s => (s.assigned, s.writesMemory, s.writesStorage, s.exits)

-- Assignments at any depth; declarations and reads are not assignments;
-- `p.slot := …` assigns `p`. Reading storage writes nothing.
#guard summary? yulBlock == some (["t", "q", "p", "u"], false, false, false)
#guard summary? "{\"nodeType\":\"YulBlock\",\"statements\":[]}" == some ([], false, false, false)
#guard summary? (calling "mstore") == some ([], true, false, false)
#guard summary? (calling "sstore") == some ([], false, true, false)
#guard summary? (calling "call") == some ([], true, true, false)
#guard summary? (calling "staticcall") == some ([], true, false, false)
#guard summary? (calling "return") == some ([], false, false, true)
#guard summary? (calling "keccak256") == some ([], false, false, false)
-- Not a Yul AST: the caller assumes the block may do anything.
#guard summary? "" == none
#guard summary? "{\"statements\":[]}" == none
#guard summary? "\"sstore(0, 1)\"" == none

/-! ## Which calls run code outside the contract -/

#guard functionTypeAttributes "function (address) view external returns (uint256)" == ["view", "external"]
#guard functionTypeAttributes "function () payable external" == ["payable", "external"]
#guard functionTypeAttributes "function (bytes memory) payable returns (bool,bytes memory)" == ["payable"]
-- A function-typed parameter's attributes are not the function's.
#guard functionTypeAttributes "function (function (uint256) external returns (uint256)) pure" == ["pure"]
#guard functionTypeAttributes "uint256" == []

private def kind? (ts : String) (member : Option String := none) : Option String :=
  (externalCallKind? (some ts) member).map fun
    | .static => "static" | .call => "call" | .delegate => "delegate"

#guard kind? "function (address) view external returns (uint256)" == some "static"
#guard kind? "function (address,uint256) external returns (bool)" == some "call"
#guard kind? "function (bytes memory) payable returns (bool,bytes memory)" "call" == some "call"
#guard kind? "function (bytes memory) returns (bool,bytes memory)" "delegatecall" == some "delegate"
#guard kind? "function (bytes memory) view returns (bool,bytes memory)" "staticcall" == some "static"
-- Internal and library functions, `send` and `transfer`.
#guard kind? "function (uint256) pure returns (uint256)" == none
#guard kind? "function (uint256) returns (uint256)" "extm" == none
#guard kind? "function (uint256) returns (bool)" "send" == none
#guard kind? "function (uint256)" "transfer" == none

end Strata.Solidity.ExprTranslator.Tests
