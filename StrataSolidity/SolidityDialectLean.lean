/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/
module

public import Strata.DDM.AST
public import Strata.DDM.BuiltinDialects.Init
import Strata.DDM.BuiltinDialects.BuiltinM

/-!
# Solidity DDM dialect — Lean source of truth (Group A)

This file is the **target** for Group A of the pipeline-language-rationalization
spec (`.kiro/specs/pipeline-language-rationalization/`). When complete, it will
replace `Tools/Solidity/src/base_dialect.py` as the canonical definition of the
Solidity DDM dialect; the existing `Solidity.dialect.st.ion` artifact will be
generated from this Lean value via a `lake gen-dialect` script (REQ-LCD-002).

## Status: SCAFFOLD

The current `StrataSolidity/SolidityDialect.lean` still loads the Python-built
Ion file via `#load_dialect`. This file lives next to it and will eventually
take over. To complete the migration:

1. Mirror every `Sol.add_op(...)` call in `Tools/Solidity/src/base_dialect.py`
   via `declareOp { name, argDecls, ..., category }` here. There are about 30
   operations across these categories: top-level, modifiers, functions,
   statements, expressions, structs/enums, type names.

2. Add `lake gen-dialect` to `lakefile.lean` that runs `IO.main` here and
   writes `Tools/Solidity/dialects/Solidity.dialect.st.ion` via Strata's Ion
   encoder.

3. Verify byte-equality between the Ion file regenerated from this Lean source
   and the Python-built one. Add this as a CI check (REQ-LCD-005).

4. Switch `SolidityDialect.lean` to import this file (or move the contents
   here) and stop using `#load_dialect`.

5. Decide the fate of `Tools/Solidity/src/base_dialect.py`:
   - Delete it (REQ-LCD-014): no consumer needs Python-side dialect.
   - Or auto-generate it from this Lean source if Python tooling still wants
     a programmatic API (currently nothing reads from it after Ion is built).

## Why a separate file during transition

Keeping this scaffold parallel to the existing `#load_dialect`-based file lets
us land an equivalence check (Lean-built dialect == Ion-loaded dialect) before
flipping the default. That lines up with REQ-MIGR-002 (parallel-run window
before any non-reversible step).
-/

open Strata.Elab

public section
namespace Strata.Solidity

/-- Imperative dialect builder mirroring `Tools/Solidity/src/base_dialect.py`'s
    `gen_dialect()`. Each `Sol.add_op(...)` line in Python becomes a
    `declareOp { ... }` call here. Each `Sol.add_syncat(...)` becomes
    `declareCat`.

    TODO(group-a): fill in all ~30 operations. Currently a stub that establishes
    the structure and proves the build path works.
-/
def soliditydialectLean : Strata.Dialect := BuiltinM.create! "SolidityLean" #[initDialect] do
  -- Syntax categories (REQ-LCD-001 / base_dialect.py:31-34)
  declareCat q`SolidityLean.node
  declareCat q`SolidityLean.opt_node
  declareCat q`SolidityLean.type_name
  declareCat q`SolidityLean.opt_type_name

  -- TODO(group-a): the ~30 operations. Pattern for each:
  --
  --   declareOp {
  --     name := "ContractDefinition",
  --     argDecls := ArgDecls.ofArray #[
  --       { ident := ⟨"name", default⟩, kind := .cat (.atom .none q`Init.Str) },
  --       { ident := ⟨"contractKind", default⟩, kind := .cat (.atom .none q`Init.Str) },
  --       ... ],
  --     category := q`SolidityLean.node,
  --     syntaxDef := <minimal — Solidity is never parsed from text in Lean>
  --   }
  --
  -- The full list lives in base_dialect.py, which is the byte-for-byte
  -- migration target. Use that file as the spec for this loop.

  -- For now: just declare the optional-node wrappers as a sanity check.
  declareOp {
    name := "missing_node",
    argDecls := .empty,
    category := q`SolidityLean.opt_node,
    syntaxDef := default
  }
  declareOp {
    name := "missing_type_name",
    argDecls := .empty,
    category := q`SolidityLean.opt_type_name,
    syntaxDef := default
  }

end Strata.Solidity
end
