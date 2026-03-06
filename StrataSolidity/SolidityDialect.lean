/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/
module

public import Strata.DDM.Integration.Lean

import Strata.DDM.AST
import Strata.DDM.Util.ByteArray
import Strata.DDM.Format
import Strata.DDM.BuiltinDialects.Init
public import Strata.DDM.Integration.Lean.OfAstM

public section
namespace Strata.Solidity
#load_dialect "../../../Tools/Solidity/dialects/Solidity.dialect.st.ion"

#strata_gen Solidity

end Strata.Solidity
end
