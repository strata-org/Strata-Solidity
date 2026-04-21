/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

-- Solidity front-end: DDM dialect, Ion reader, and AST → Laurel translation.

import StrataSolidity.SolidityDialect
import StrataSolidity.ReadSolidity
import StrataSolidity.SolTranslator.Types
import StrataSolidity.SolTranslator.SpecParser
import StrataSolidity.SolTranslator.SpecRewriter
import StrataSolidity.SolTranslator.ExprTranslator
import StrataSolidity.SolTranslator.StmtTranslator
import StrataSolidity.SolTranslator.ContractTranslator
