/-
  Copyright Strata Contributors

  SPDX-License-Identifier: Apache-2.0 OR MIT
-/
module

public import Strata.DDM.AST
public import Strata.DDM.Integration.Lean

/-!
# Solidity DDM dialect — Lean source of truth (Group A)

Lean equivalent of `Tools/Solidity/src/base_dialect.py`'s `gen_dialect()`.
This file defines the Solidity DDM dialect using DDM's *declarative* dialect
syntax (the `#dialect … #end` command), rather than programmatic
`declareOp` calls — per review feedback on PR #23 and the DDM manual:
https://strata-org.github.io/Strata/ddm/html-single/

## Why declarative

- The dialect reads top-to-bottom like a grammar: `op Name (arg : cat, …) :
  cat => syntax;` — the same shape the DDM manual documents and the other
  Strata dialects (Core, B3, C_Simp, SMT) use.
- Each op also gets a concrete display syntax (`Name(arg, …)`), so DDM can
  pretty-print Solidity AST values for debugging — the programmatic
  `syntaxDef := default` version could not.

## Structure

Mirrors `base_dialect.py` section-for-section:
  1. Four syntax categories: `node`, `opt_node`, `type_name`, `opt_type_name`.
  2. Four optional-wrapper ops: `some_node` / `missing_node`,
     `some_type_name` / `missing_type_name`.
  3. ~50 AST node ops grouped by area: top-level, definitions, statements,
     expressions, events/errors, structs/enums, type names.

## Parity check

`lake exe gen-dialect-summary` prints this dialect's structural summary;
CI diffs it against `Tools/Solidity/src/print_dialect_summary.py`'s output
from `base_dialect.py` on every push (Group A step 3). Keep the two in sync.
-/

namespace Strata.Solidity

#dialect
dialect SolidityLean;

// ── Syntax categories ────────────────────────────────────────────────
category node;
category opt_node;
category type_name;
category opt_type_name;

// ── Optional-node wrappers ───────────────────────────────────────────
op some_node (x : node) : opt_node =>
  "some_node(" x ")";
op missing_node : opt_node => "missing_node";
op some_type_name (x : type_name) : opt_type_name =>
  "some_type_name(" x ")";
op missing_type_name : opt_type_name => "missing_type_name";

// ── Top-level ────────────────────────────────────────────────────────
op SourceUnit (nodes : Seq node) : Command =>
  "SourceUnit(" nodes ")";
op PragmaDirective (literals : Seq Str) : node =>
  "PragmaDirective(" literals ")";
op ImportDirective (
    file : Str,
    absolutePath : Str,
    unitAlias : Str,
    symbolAliases : Seq Str) : node =>
  "ImportDirective(" file ", " absolutePath ", " unitAlias ", " symbolAliases ")";

// ── Definitions ──────────────────────────────────────────────────────
op ContractDefinition (
    name : Str,
    contractKind : Str,
    abstract : Str,
    nodes : Seq node,
    documentation : Str,
    baseContracts : Seq Str) : node =>
  "ContractDefinition(" name ", " contractKind ", " abstract ", " nodes ", " documentation ", " baseContracts ")";
op UserDefinedValueTypeDefinition (name : Str, underlyingType : type_name) : node =>
  "UserDefinedValueTypeDefinition(" name ", " underlyingType ")";
op ModifierDefinition (name : Str, parameters : node, body : opt_node) : node =>
  "ModifierDefinition(" name ", " parameters ", " body ")";
op ModifierInvocation (modifierName : Str, arguments : Seq node) : node =>
  "ModifierInvocation(" modifierName ", " arguments ")";
op FunctionDefinition (
    name : Str,
    kind : Str,
    stateMutability : Str,
    visibility : Str,
    virtual : Str,
    parameters : node,
    returnParameters : node,
    body : opt_node,
    documentation : Str,
    modifiers : Seq node) : node =>
  "FunctionDefinition(" name ", " kind ", " stateMutability ", " visibility ", " virtual ", " parameters ", " returnParameters ", " body ", " documentation ", " modifiers ")";
op ParameterList (parameters : Seq node) : node =>
  "ParameterList(" parameters ")";
op VariableDeclaration (
    name : Str,
    typeName : opt_type_name,
    stateVariable : Str,
    constant : Str,
    mutability : Str,
    visibility : Str,
    indexed : Str,
    storageLocation : Str,
    value : opt_node,
    documentation : Str) : node =>
  "VariableDeclaration(" name ", " typeName ", " stateVariable ", " constant ", " mutability ", " visibility ", " indexed ", " storageLocation ", " value ", " documentation ")";

// ── Statements ───────────────────────────────────────────────────────
op Block (statements : Seq node) : node =>
  "Block(" statements ")";
op UncheckedBlock (statements : Seq node) : node =>
  "UncheckedBlock(" statements ")";
op ExpressionStatement (expression : node) : node =>
  "ExpressionStatement(" expression ")";
op Return (expression : opt_node) : node =>
  "Return(" expression ")";
op IfStatement (condition : node, trueBody : node, falseBody : opt_node) : node =>
  "IfStatement(" condition ", " trueBody ", " falseBody ")";
op WhileStatement (condition : node, body : node) : node =>
  "WhileStatement(" condition ", " body ")";
op ForStatement (
    initializationExpression : opt_node,
    condition : opt_node,
    loopExpression : opt_node,
    body : node) : node =>
  "ForStatement(" initializationExpression ", " condition ", " loopExpression ", " body ")";
op DoWhileStatement (condition : node, body : node) : node =>
  "DoWhileStatement(" condition ", " body ")";
op BreakStatement : node => "BreakStatement";
op ContinueStatement : node => "ContinueStatement";
op TryStatement (externalCall : node, clauses : Seq node) : node =>
  "TryStatement(" externalCall ", " clauses ")";
op TryCatchClause (errorName : Str, parameters : opt_node, block : node) : node =>
  "TryCatchClause(" errorName ", " parameters ", " block ")";
op VariableDeclarationStatement (declarations : Seq opt_node, initialValue : opt_node) : node =>
  "VariableDeclarationStatement(" declarations ", " initialValue ")";
op InlineAssembly (yul : Str) : node =>
  "InlineAssembly(" yul ")";

// ── Expressions ──────────────────────────────────────────────────────
op Assignment (leftHandSide : node, rightHandSide : node, operator : Str) : node =>
  "Assignment(" leftHandSide ", " rightHandSide ", " operator ")";
op BinaryOperation (leftExpression : node, rightExpression : node, operator : Str) : node =>
  "BinaryOperation(" leftExpression ", " rightExpression ", " operator ")";
op UnaryOperation (subExpression : node, operator : Str, prefix : Str) : node =>
  "UnaryOperation(" subExpression ", " operator ", " prefix ")";
op FunctionCall (expression : node, arguments : Seq node, kind : Str, names : Seq Str) : node =>
  "FunctionCall(" expression ", " arguments ", " kind ", " names ")";
op FunctionCallOptions (expression : node, names : Seq Str, options : Seq node) : node =>
  "FunctionCallOptions(" expression ", " names ", " options ")";
op NewExpression (typeName : type_name) : node =>
  "NewExpression(" typeName ")";
op Identifier (name : Str) : node =>
  "Identifier(" name ")";
op Literal (value : Str, kind : Str, subdenomination : Str) : node =>
  "Literal(" value ", " kind ", " subdenomination ")";
op MemberAccess (expression : node, memberName : Str) : node =>
  "MemberAccess(" expression ", " memberName ")";
op IndexAccess (baseExpression : node, indexExpression : opt_node) : node =>
  "IndexAccess(" baseExpression ", " indexExpression ")";
op IndexRangeAccess (
    baseExpression : node,
    startExpression : opt_node,
    endExpression : opt_node) : node =>
  "IndexRangeAccess(" baseExpression ", " startExpression ", " endExpression ")";
op InlineArrayExpression (components : Seq node) : node =>
  "InlineArrayExpression(" components ")";
op Conditional (condition : node, trueExpression : node, falseExpression : node) : node =>
  "Conditional(" condition ", " trueExpression ", " falseExpression ")";
op TupleExpression (components : Seq node) : node =>
  "TupleExpression(" components ")";
op ElementaryTypeNameExpression (typeName : Str) : node =>
  "ElementaryTypeNameExpression(" typeName ")";

// ── Events and custom errors ─────────────────────────────────────────
op EventDefinition (name : Str, parameters : node, anonymous : Str) : node =>
  "EventDefinition(" name ", " parameters ", " anonymous ")";
op ErrorDefinition (name : Str, parameters : node) : node =>
  "ErrorDefinition(" name ", " parameters ")";
op EmitStatement (eventCall : node) : node =>
  "EmitStatement(" eventCall ")";
op RevertStatement (errorCall : node) : node =>
  "RevertStatement(" errorCall ")";

// ── Structs and enums ────────────────────────────────────────────────
op StructDefinition (name : Str, members : Seq node) : node =>
  "StructDefinition(" name ", " members ")";
op EnumDefinition (name : Str, members : Seq node) : node =>
  "EnumDefinition(" name ", " members ")";
op EnumValue (name : Str) : node =>
  "EnumValue(" name ")";
op UsingForDirective (libraryName : Str, typeName : opt_type_name, global : Str) : node =>
  "UsingForDirective(" libraryName ", " typeName ", " global ")";

// ── Type names ───────────────────────────────────────────────────────
op ElementaryTypeName (name : Str, stateMutability : Str) : type_name =>
  "ElementaryTypeName(" name ", " stateMutability ")";
op UserDefinedTypeName (name : Str) : type_name =>
  "UserDefinedTypeName(" name ")";
op MappingType (
    keyType : type_name,
    valueType : type_name,
    keyName : Str,
    valueName : Str) : type_name =>
  "MappingType(" keyType ", " valueType ", " keyName ", " valueName ")";
op ArrayTypeName (baseType : type_name) : type_name =>
  "ArrayTypeName(" baseType ")";
op FunctionTypeName (
    parameterTypes : node,
    returnParameterTypes : node,
    visibility : Str,
    stateMutability : Str) : type_name =>
  "FunctionTypeName(" parameterTypes ", " returnParameterTypes ", " visibility ", " stateMutability ")";

#end

/-- The Lean-canonical Solidity DDM dialect (declared via `#dialect` above).
    Alias kept so existing consumers (`DialectSummary.lean`, the parity CI
    gate) are unaffected by the declarative rewrite. -/
public def soliditydialectLean : Strata.Dialect := SolidityLean

end Strata.Solidity
