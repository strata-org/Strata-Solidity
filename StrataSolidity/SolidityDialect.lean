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
-- `#load_dialect` resolves relative to this Lean file's directory
-- (Strata/.../HashCommands.lean::resolveLeanRelPath). This file lives at
-- `<repo>/StrataSolidity/SolidityDialect.lean`, so one `..` reaches the
-- repo root and the dialect lives at `<repo>/Tools/Solidity/dialects/`.
-- The previous `../../../Tools/...` path resolved to a sibling checkout
-- on a developer machine and broke on CI (REQ-STRATA-005, design §14.2).
#load_dialect "../Tools/Solidity/dialects/Solidity.dialect.st.ion"

#strata_gen Solidity

end Strata.Solidity
end
