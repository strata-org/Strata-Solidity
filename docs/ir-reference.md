# Strata IR Reference — Laurel & Core

## Pipeline Overview

```
Solidity → [solast.py] → Ion AST → [StrataSolidity] → Laurel IR → [Strata Core] → Core IR → [VCG] → SMT-LIB → [z3] → pass/fail
```

---

## Laurel IR

Laurel is the high-level intermediate verification language. It's the target for all source language translators (Java/jVerify, Python, Solidity/StrataSolidity). It preserves structured control flow and high-level types.

### Syntax (textual format)

```
procedure Name(x: int, y: bool) returns (r: int)
  requires x > 0
  ensures r == x + 1
  modifies someGlobal
{
  r := x + 1;
};
```

### Types (`HighType`)

| Type | Description |
|------|-------------|
| `int` | Arbitrary-precision integer |
| `bool` | Boolean |
| `float64` | 64-bit float |
| `string` | String |
| `void` | No value |
| `Map[K, V]` | Map/dictionary type |
| `Set[T]` | Set type |
| `UserDefined(name)` | Composite/struct type |
| `Pure(T)` | Value type (structural equality) |

### Expressions (`StmtExpr`)

Laurel unifies statements and expressions into a single `StmtExpr` type:

**Literals:** `LiteralInt`, `LiteralBool`, `LiteralString`

**Variables:** `Identifier(name)`, `LocalVariable(name, type, init?)`

**Operations:** `PrimitiveOp(op, args)` where `op` is:
- Arithmetic: `Add`, `Sub`, `Mul`, `Div`, `Mod`, `DivT`, `ModT`, `Neg`
- Comparison: `Lt`, `Leq`, `Gt`, `Geq`, `Eq`, `Neq`
- Logical: `And`, `Or`, `Not`, `Implies`
- String: `StrConcat`

**Control flow:**
- `IfThenElse(cond, then, else?)`
- `While(cond, invariants, decreases?, body)`
- `Block(stmts, label?)`
- `Exit(label)` — break/continue
- `Return(value?)`

**Assignment:** `Assign(targets, value)`

**Calls:** `StaticCall(callee, args)`, `InstanceCall(target, callee, args)`

**Heap/objects:** `FieldSelect(target, field)`, `New(ref)`, `This`

**Specification constructs:**
- `Old(expr)` — pre-state value in postconditions
- `Forall(param, body)` — universal quantification
- `Exists(param, body)` — existential quantification
- `Assert(cond)` — proof obligation
- `Assume(cond)` — restrict state space
- `Fresh(value)` — newly allocated reference

### Procedures

```lean
structure Procedure where
  name : Identifier
  inputs : List Parameter        -- input params
  outputs : List Parameter       -- output params (multiple allowed)
  preconditions : List StmtExpr  -- requires clauses
  body : Body                    -- Transparent | Opaque | Abstract | External
```

**Body variants:**
- `Transparent(body)` — implementation visible to callers
- `Opaque(postconditions, implementation?, modifies)` — callers only see spec
- `Abstract(postconditions)` — must be overridden
- `External` — built-in, not translated

### How StrataSolidity generates Laurel

Each Solidity function becomes an `Opaque` procedure:
- `requires` annotations → `preconditions`
- `ensures` annotations → `postconditions`
- `modifies` annotations → `modifies` list
- Function body → `implementation`
- State variables → extra input/output parameters (mappings) or composite fields (scalars)
- `old(x)` → `Old` node referencing input parameter

Frame conditions (`modifies balances[msg.sender]`) generate:
```
Forall(__k : int,
  PrimitiveOp(Implies, [
    PrimitiveOp(Neq, [Identifier(__k), Identifier(msg_sender)]),
    PrimitiveOp(Eq, [select(balances, __k), select(balances_in, __k)])
  ]))
```

---

## Strata Core IR

Core is the low-level verification language, roughly equivalent to Boogie. Laurel is translated to Core during verification. Core has:
- Flat procedures (no objects/heap — heap is parameterized away)
- Explicit `spec {}` blocks
- `old` for pre-state references
- Maps with `select`/`update` (SMT array theory)
- Axioms and uninterpreted functions

### Syntax

```
program Core;

type MyType;                          -- abstract type
var g : bool;                         -- global variable
const c : int;                        -- global constant

function f(x: int): int;             -- uninterpreted function
function f2(x: int): int { x + 1 }  -- defined function

axiom [name]: forall x: int :: f(x) >= 0;

procedure Test(x: int) returns (y: int)
spec {
  modifies g;
  requires x > 0;
  ensures y == x + 1;
  ensures g == old g;
  free requires x >= 0;              -- assumed, not checked at call sites
  free ensures y >= 0;               -- assumed, not proved
}
{
  y := x + 1;
};
```

### Types

| Type | Description |
|------|-------------|
| `int` | Unbounded integer |
| `bool` | Boolean |
| `string` | String |
| `Map[K, V]` | SMT array (select/update) |
| `Ref` | Heap reference (for OOP languages) |
| `Box` | Boxed value (for polymorphism) |
| User-defined | Abstract types declared with `type Name;` |

### Key constructs

**Map operations:**
- `m[k]` — select (read from map)
- `m[k := v]` — update (write to map, produces new map)

**Quantifiers:**
- `forall x: T :: body`
- `exists x: T :: body`
- `{ expr }` — trigger/pattern for quantifier instantiation

**Spec clauses:**
- `requires P` — precondition (caller must establish)
- `ensures Q` — postcondition (callee must establish)
- `modifies g` — frame condition (only listed globals may change)
- `free requires P` — assumed but not checked at call sites
- `free ensures Q` — assumed but not proved in body
- `old expr` — value of expr at procedure entry

**Statements:**
- `var x: T := e;` — local variable
- `x := e;` — assignment
- `assert [label]: P;` — proof obligation
- `assume P;` — restrict execution paths
- `call x := Proc(args);` — procedure call
- `if (c) { ... } else { ... }`
- `while (c) invariant I { ... }`

### Verification Condition Generation (VCG)

Core's VCG produces one proof obligation per `assert` and per `ensures` clause. Each obligation becomes an SMT-LIB query:

```smt2
(set-logic ALL)
(declare-fun balances_in () (Array Int Int))
(declare-fun balances () (Array Int Int))
(declare-fun msg_sender () Int)
(declare-fun amount () Int)
; ... preconditions as assertions ...
(assert (not (= (select balances msg_sender)
               (- (select balances_in msg_sender) amount))))
(check-sat)
; unsat = obligation proved
```

### How Laurel maps to Core

| Laurel | Core |
|--------|------|
| `Procedure` with `Opaque` body | `procedure` with `spec {}` block |
| `HighType.TInt` | `int` |
| `HighType.TMap` | `Map[K, V]` |
| `HighType.UserDefined` | Composite type or abstract type |
| `StmtExpr.Forall` | `forall` in spec |
| `StmtExpr.Old` | `old` in ensures |
| `StmtExpr.FieldSelect` | Map select after heap parameterization |
| Object fields | Flattened to map operations |

---

## SMT-LIB Output

The final stage. Each proof obligation becomes a separate SMT-LIB query:
- `unsat` → obligation proved (no counterexample exists)
- `sat` → obligation may be violated
- `unknown`/`timeout` → solver couldn't decide

Key SMT theories used:
- `QF_LIA` / `LIA` — linear integer arithmetic
- `Arrays` — for mappings (`select`, `store`)
- Uninterpreted functions — for `keccak256`, `sum_mapping`, etc.

---

## StrataSolidity-specific patterns

### Mapping state variables
Solidity `mapping(address => uint256) balances` becomes:
- Input param: `balances_in : Map[int, int]`
- Output param: `balances : Map[int, int]`
- Access: `select(balances, key)` / `update(balances, key, val)`

### Scalar state variables
Solidity `uint256 totalSupply` becomes:
- Input param: `__old_totalSupply : int`
- Output param: `totalSupply : int`

### sum() aggregate
Uninterpreted function with update axiom:
```
function sum_balances(m: Map[int, int]): int;
axiom: forall m: Map[int,int], k: int, v: int ::
  sum_balances(update(m, k, v)) == sum_balances(m) - select(m, k) + v
```

### Constructor handling
- Invariants checked as postconditions (establish)
- No `self` parameter, no `modifies self`
- State vars referenced directly as output params
