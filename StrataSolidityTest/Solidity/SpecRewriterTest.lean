/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

/-
  Unit tests for Strata Solidity spec rewriting passes.
-/
import StrataSolidity.SolTranslator.SpecRewriter
import StrataSolidity.SolTranslator.Types

namespace Strata.Solidity.SpecRewriter.Tests

open Strata.Solidity
open Laurel

private def isIdent (e : StmtExprMd) (name : String) : Bool :=
  match e.val with | .Var (.Local n) => n.text == name | _ => false

private def isFieldSelect (e : StmtExprMd) (obj field : String) : Bool :=
  match e.val with
  | .Var (.Field base f) =>
    match base.val with
    | .Var (.Local n) => n.text == obj && f.text == field
    | _ => false
  | _ => false

/-! ## rewriteMappingIdsToIn -/

-- balances → balances_in
#guard isIdent (rewriteMappingIdsToIn ["balances"] (mkStmtExprMd (mkIdentifier "balances"))) "balances_in"

-- x (not a mapping) → x (unchanged)
#guard isIdent (rewriteMappingIdsToIn ["balances"] (mkStmtExprMd (mkIdentifier "x"))) "x"

/-! ## rewriteStateVarRefs -/

-- scalar state var: count → FieldSelect self "count"
#guard isFieldSelect (rewriteStateVarRefs ["count"] [] [] (mkStmtExprMd (mkIdentifier "count"))) "self" "count"

-- mapping state var: balances → balances (unchanged)
#guard isIdent (rewriteStateVarRefs ["balances"] ["balances"] [] (mkStmtExprMd (mkIdentifier "balances"))) "balances"

-- local var: i → i (unchanged)
#guard isIdent (rewriteStateVarRefs ["count"] [] ["i"] (mkStmtExprMd (mkIdentifier "i"))) "i"

/-! ## processOldMarkers -/

-- old(mapping) → mapping_in
private def testOldMapping : Bool :=
  let inner := mkStmtExprMd (mkIdentifier "balances")
  let expr := mkStmtExprMd (.StaticCall "__old" [inner])
  let result := processOldMarkers ["balances"] [] [] expr
  isIdent result "balances_in"

#guard testOldMapping

-- old(scalar) → __old_count marker
private def testOldScalar : Bool :=
  let inner := mkStmtExprMd (mkIdentifier "count")
  let expr := mkStmtExprMd (.StaticCall "__old" [inner])
  let result := processOldMarkers [] [] ["count"] expr
  isIdent result "__old_count"

#guard testOldScalar

end Strata.Solidity.SpecRewriter.Tests
