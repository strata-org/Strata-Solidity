/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

-- Placeholder: Solidity AST → Laurel translation.
-- Will be implemented once the DDM dialect and Ion reader are in place.

import Strata.Languages.Laurel.Laurel

namespace Strata.Solidity

/-- Placeholder for the Solidity-to-Laurel translator. -/
def translateToLaurel : Except String Strata.Laurel.Program :=
  .error "Solidity front-end not yet implemented"

end Strata.Solidity
