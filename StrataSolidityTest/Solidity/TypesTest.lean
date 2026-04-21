/-
  Unit tests for Strata Solidity type translation.
-/
import StrataSolidity.SolTranslator.Types

namespace Strata.Solidity.Types.Tests

open Strata.Solidity
open Laurel

/-! ## Type translation tests -/

private def isInt (st : SolType) : Bool :=
  match st.highType.val with | .TInt => true | _ => false

private def isBool (st : SolType) : Bool :=
  match st.highType.val with | .TBool => true | _ => false

#guard isInt (translateTypeName "uint256")
#guard isInt (translateTypeName "int256")
#guard isInt (translateTypeName "address")
#guard isBool (translateTypeName "bool")
#guard isInt (translateTypeName "bytes32")
#guard isInt (translateTypeName "uint8")
#guard isInt (translateTypeName "uint128")

/-! ## Uint bounds detection -/

#guard (translateTypeName "uint256").isUint == true
#guard (translateTypeName "uint8").isUint == true
#guard (translateTypeName "int256").isUint == false
#guard (translateTypeName "bool").isUint == false
#guard (translateTypeName "address").isAddress == true
#guard (translateTypeName "bytes32").isBytes == true

/-! ## Default values -/

private def isLitInt (e : StmtExprMd) (v : Int) : Bool :=
  match e.val with | .LiteralInt n => n == v | _ => false

private def isLitBool (e : StmtExprMd) (v : Bool) : Bool :=
  match e.val with | .LiteralBool b => b == v | _ => false

#guard isLitInt (defaultValueForType (mkHighTypeMd .TInt)) 0
#guard isLitBool (defaultValueForType (mkHighTypeMd .TBool)) false

/-! ## Helper: mkNonNegPrecond -/

private def isGeqZero (e : StmtExprMd) (name : String) : Bool :=
  match e.val with
  | .PrimitiveOp .Geq [lhs, rhs] =>
    match lhs.val, rhs.val with
    | .Identifier n, .LiteralInt 0 => n.text == name
    | _, _ => false
  | _ => false

#guard isGeqZero (mkNonNegPrecond "x") "x"
#guard isGeqZero (mkNonNegPrecond "amount") "amount"

end Strata.Solidity.Types.Tests
