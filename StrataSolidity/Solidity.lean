/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/

-- Solidity front-end: DDM dialect, Ion reader, and AST → Laurel translation.

import StrataSolidity.SolidityDialect
-- Parallel Lean-source-of-truth dialect (Group A step 1, PR #5). Imported
-- here so it's part of the default `lake build` set — without this the
-- file lives orphan in the lib dir and only builds when
-- `lake exe gen-dialect-summary` is invoked, which lets compilation
-- regressions slip past CI's `lake build` step.
import StrataSolidity.SolidityDialectLean
-- Group B scaffolds (PR #18). Same orphan story: not yet wired into the
-- production pipeline (which still goes through solast.py + ReadSolidity),
-- but importing here ensures `lake build` compiles them so syntax/type
-- regressions are caught before they reach the Group B step 2 author.
import StrataSolidity.SolcRunner
import StrataSolidity.SolcAstParser
-- DDM-parser scaffold (PR #6). Currently a doc + grammar sketch; importing
-- here gates compilation so the migration plan stays buildable as the
-- Layer-2 spec parser is incrementally replaced.
import StrataSolidity.SpecGrammar
import StrataSolidity.ReadSolidity
import StrataSolidity.SolTranslator.Types
import StrataSolidity.SolTranslator.SpecParser
import StrataSolidity.SolTranslator.SpecRewriter
import StrataSolidity.SolTranslator.ExprTranslator
import StrataSolidity.SolTranslator.StmtTranslator
import StrataSolidity.SolTranslator.ContractTranslator
