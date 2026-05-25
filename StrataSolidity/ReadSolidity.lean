/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/
module

import Strata.DDM.Ion
import Strata.DDM.Util.Ion
public import StrataSolidity.SolidityDialect

public section
namespace Strata.Solidity

/-- Read a Solidity Ion file and return the top-level DDM commands. -/
private def readSolidityStrataBytes (strataPath : String) (bytes : ByteArray)
    : Except String (Array (Strata.Solidity.Command SourceRange)) := do
  if ! Ion.isIonFile bytes then
    throw s!"{strataPath} is not an Ion file."
  match Strata.Program.fromIon Strata.Solidity.Solidity_map Strata.Solidity.Solidity.name bytes with
  | .ok pgm =>
    let cmds ← pgm.commands.mapM fun cmd =>
      match Strata.Solidity.Command.ofAst cmd with
      | .error msg => throw s!"Error reading {strataPath}: {msg}"
      | .ok r => pure r
    pure cmds
  | .error msg =>
    throw s!"Error reading {strataPath}: {msg}"

/-- Read a pre-compiled Strata Ion file containing a Solidity AST. -/
def readSolidityStrata (strataPath : String)
    : EIO String (Array (Strata.Solidity.Command SourceRange)) := do
  let bytes ←
    match ← IO.FS.readBinFile strataPath |>.toBaseIO with
    | .ok b => pure b
    | .error msg => throw s!"Error reading {strataPath}: {msg}"
  match readSolidityStrataBytes strataPath bytes with
  | .ok r => pure r
  | .error msg => throw msg

end Strata.Solidity
end
