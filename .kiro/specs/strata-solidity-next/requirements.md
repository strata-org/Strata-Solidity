# Requirements Document — `strata-solidity-next`

## Introduction

This document holds the requirements that change behavior relative to the
**retrospective baseline** in
[`../strata-solidity-baseline/requirements.md`](../strata-solidity-baseline/requirements.md).
The baseline describes what the code did when it was written and introduces
no new behavior; this document is the only place where its `GAP-*` items
are closed.

Every requirement below cites the baseline IDs it modifies or closes, as
`CONTRIBUTING.md` requires. Baseline requirements not cited here are
unchanged.

---

### Requirement 1 — Inheritance: a contract is verified with its inherited members

**Closes:** `GAP-009` (multi-contract inheritance with virtual dispatch),
except for the cases REQ-NEXT-SOL-022..025 report or reject.
**Modifies:** `REQ-SOL-004` (single inheritance via `is`),
`REQ-SOL-005` (diamond inheritance via `baseContracts`),
`REQ-SOL-006` (virtual dispatch across contracts).

**User Story:** As a developer verifying a contract that inherits from
another, I want what it inherits to be part of what is verified, so that a
contract built from base contracts can be specified and proven at all.

**Context.** The baseline's `REQ-SOL-004` and `REQ-SOL-005` say inheritance
is accepted "flattened at the AST level", and `design.md` §12.9 attributes
that flattening to `solast.py`. Neither held once the in-Lean frontend
replaced the Python one: solc's AST lists only the members written in a
contract, with its bases named in `baseContracts`, and
`ContractTranslator.translateContract` read only a contract's own members,
so any use of an inherited member failed to translate. These requirements
replace that behavior.

#### Acceptance Criteria — Flattening

1. REQ-NEXT-SOL-001. THE Solidity_Translator SHALL verify a contract as the
   flattening of its transitive bases and itself, so that every inherited
   member resolves in the derived contract's own context (its `self`
   parameter, its state parameters, its invariants).
2. REQ-NEXT-SOL-002. THE Solidity_Translator SHALL order a contract's bases
   by solc's C3 linearization (`linearizedBaseContracts`): for
   `contract C is B1, …, Bn`, `L(C) = C :: merge(L(Bn), …, L(B1), [Bn, …, B1])`.
   Inherited members are taken most base first, the reverse of `L(C)`.
3. REQ-NEXT-SOL-003. WHERE a more derived contract declares a function with
   the name and parameter types (data locations aside) of an inherited one,
   or a `receive`, `fallback` or modifier of the same name, THE
   Solidity_Translator SHALL verify the more derived declaration and not
   the inherited one. A function of the same name with other parameter
   types is an overload, and both are verified.
4. REQ-NEXT-SOL-004. WHERE a public state variable shares its name with an
   inherited function (which its getter overrides), THE Solidity_Translator
   SHALL NOT verify that function in the deriving contract.
5. REQ-NEXT-SOL-005. THE Solidity_Translator SHALL merge inherited state
   variables together with their initializers, `constant` values,
   `immutable` markers and Solidity type names, and inherited structs,
   enums and modifier definitions.
6. REQ-NEXT-SOL-006. THE Solidity_Translator SHALL emit a struct's type
   definition and its synthetic constructor procedure once, for the
   contract that declares the struct.
7. REQ-NEXT-SOL-007. THE Solidity_Translator SHALL continue to verify every
   contract of the file on its own, so that a base's specifications are
   checked against the base as well as against each contract that inherits
   them; an obligation of an inherited function SHALL name the contract it
   is checked in (`ensures … (in D)`).
8. REQ-NEXT-SOL-008. WHERE an inherited function calls a virtual function,
   THE Solidity_Translator SHALL call the most derived override of it.

#### Acceptance Criteria — Invariants

9. REQ-NEXT-SOL-009. THE Solidity_Translator SHALL check a base contract's
   `@custom:strata invariant`, whether written in the base's NatSpec or on
   one of its state variables, at the external entry points of every
   contract that inherits it, under the rules of `REQ-SPEC-*` for the
   deriving contract.
10. REQ-NEXT-SOL-010. WHERE a base is an `interface` or a `library`, which
    have no state, THE Solidity_Translator SHALL NOT take invariants from
    it.

#### Acceptance Criteria — Constructors

11. REQ-NEXT-SOL-011. THE Solidity_Translator SHALL run each base
    constructor when a deriving contract's constructor (explicit, or the
    implicit one that checks the initial state) runs: after every
    state-variable initializer, before the deriving constructor and outside
    its modifiers, most base first (solc's legacy code generator order).
12. REQ-NEXT-SOL-012. THE Solidity_Translator SHALL run a base constructor
    with its own modifiers, in a block that a `return` in it exits, with its
    parameters and locals renamed apart from the deriving constructor's.
13. REQ-NEXT-SOL-013. THE Solidity_Translator SHALL bind a base
    constructor's parameters to the arguments that the most derived
    constructor naming its contract gives (`constructor() Base(7)`),
    evaluated most derived first in the scope of that constructor.
14. REQ-NEXT-SOL-014. IF a base constructor's arguments are given in an
    inheritance specifier (`is Base(7)`), which the AST the translator reads
    does not carry, or not at all (an abstract contract), THEN THE
    Solidity_Translator SHALL give its parameters unknown values of their
    types.
15. REQ-NEXT-SOL-015. IF a base constructor a constructor runs uses a
    struct-valued mapping, THEN THE Solidity_Translator SHALL NOT verify
    that constructor, nor the invariants it would establish, and SHALL emit
    a warning.

#### Acceptance Criteria — `super` and explicit base calls

16. REQ-NEXT-SOL-016. THE Solidity_Translator SHALL resolve `super.f(...)`
    to the implementation of `f` that follows, in the linearization of the
    contract being verified, the contract in which the call is written: the
    contract that defines the function, modifier or base constructor it is
    in.
17. REQ-NEXT-SOL-017. THE Solidity_Translator SHALL resolve `Base.f(...)`,
    for a base `Base`, to the first implementation of `f` in `L(Base)`.
18. REQ-NEXT-SOL-018. THE Solidity_Translator SHALL emit each overridden
    implementation that such a call reaches, directly or through another
    one, as an internal procedure of the deriving contract named
    `__base_<DeclaringContract>_<function>`, and no other.
19. REQ-NEXT-SOL-019. THE Solidity_Translator SHALL bind the named
    arguments of such a call by name.
20. REQ-NEXT-SOL-020. IF such a call names an overloaded function, or has
    no implementation to call, or reaches an implementation that uses a
    struct-valued mapping, THEN THE Solidity_Translator SHALL fail with an
    `unsupported` error.

#### Acceptance Criteria — Reporting and rejection

21. REQ-NEXT-SOL-021. THE Solidity_Translator SHALL emit the warnings of
    `REQ-OUT-*` and `REQ-SPEC-*` for a contract's own declarations only, so
    that an inherited declaration is reported once, against the contract
    that declares it.
22. REQ-NEXT-SOL-022. IF a contract's linearization includes a contract
    that the verified file does not define (an imported base, directly or
    through another base), THEN THE Solidity_Translator SHALL emit a warning
    naming it and the deriving contract, and SHALL verify the contract
    without its members. This is the remaining part of `GAP-009`.
23. REQ-NEXT-SOL-023. IF a contract and one of its bases declare state
    variables of the same name (a base's private one), THEN THE
    Solidity_Translator SHALL fail with an `unsupported` error: they are
    different variables.
24. REQ-NEXT-SOL-024. Note. Overloads whose parameters are all integers or
    addresses have the same parameter types in Laurel and are rejected, in
    a single contract too (unchanged from the baseline).
25. REQ-NEXT-SOL-025. Note. Base constructors run in solc's legacy order;
    the IR code generator (`--via-ir`) initializes each contract's state
    variables just before its constructor runs.

#### Characterization

26. REQ-NEXT-TEST-001. THE Golden_Harness SHALL cover, each with true and
    false properties: inherited state, internal calls, modifiers,
    invariants, virtual dispatch and a getter override
    (`test/examples/inheritance.sol`); overloads
    (`inheritance_overloads.sol`); base constructors
    (`inheritance_constructors.sol`); C3 order
    (`inheritance_linearization.sol`); `super` and explicit base calls
    (`inheritance_super.sol`, `inheritance_diamond.sol`); and the reported
    or rejected cases (`inheritance_imported.sol`,
    `inheritance_struct_mapping.sol`, `inheritance_shadowed_state.sol`).
