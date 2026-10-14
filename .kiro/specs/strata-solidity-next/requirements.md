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

**Closes:** `GAP-009` (multi-contract inheritance, for state, internal
calls, modifiers, invariants and `super`; see the carve-out in
REQ-NEXT-SOL-016 below).
**Modifies:** `REQ-SOL-004` (single inheritance via `is`),
`REQ-SOL-005` (diamond inheritance via `baseContracts`),
`REQ-SOL-006` (virtual dispatch across contracts).

**User Story:** As a developer verifying a contract that inherits from
another, I want what it inherits to be part of what is verified, so that a
contract built from base contracts can be specified and proven at all.

**Context.** The baseline's `REQ-SOL-004` and `REQ-SOL-005` say inheritance
is accepted "flattened at the AST level", and `design.md` §12.9 attributes
that flattening to `solast.py`. Neither held once the in-Lean frontend
replaced the Python one: solc's `--standard-json` AST lists only the members
written in a contract, with its bases named in `baseContracts`, and
`ContractTranslator.translateContract` read only a contract's own members.
Any use of an inherited member therefore failed to translate. These
requirements replace that behavior.

#### Acceptance Criteria — Flattening

1. REQ-NEXT-SOL-001. THE Solidity_Translator SHALL verify a contract as the
   flattening of its transitive bases and itself, so that every inherited
   member resolves in the derived contract's own context (its `self`
   parameter, its state parameters, its invariants).
2. REQ-NEXT-SOL-002. THE Solidity_Translator SHALL order inherited members
   most-base-first, by a post-order walk of the `baseContracts` lists taken
   left to right, keeping the first occurrence of each contract. This is
   Solidity's storage layout and initialization order.
3. REQ-NEXT-SOL-003. WHERE the derived contract declares a function,
   `receive`, `fallback` or modifier whose name an inherited one also
   declares, THE Solidity_Translator SHALL verify the derived declaration
   and not the inherited one.
4. REQ-NEXT-SOL-004. THE Solidity_Translator SHALL merge inherited state
   variables together with their initializers, `constant` values,
   `immutable` markers and Solidity type names.
5. REQ-NEXT-SOL-005. THE Solidity_Translator SHALL merge inherited structs,
   enums, user-defined value types and modifier definitions.
6. REQ-NEXT-SOL-006. THE Solidity_Translator SHALL emit a struct's type
   definition and its synthetic constructor procedure once, for the contract
   that declares the struct.
7. REQ-NEXT-SOL-007. THE Solidity_Translator SHALL continue to verify every
   contract of the file on its own, so that a base's specifications are
   checked against the base as well as against each contract that inherits
   them.

#### Acceptance Criteria — Invariants

8. REQ-NEXT-SOL-010. THE Solidity_Translator SHALL check a base contract's
   `@custom:strata invariant`, whether written in the base's NatSpec or on
   one of its state variables, at the external entry points of every
   contract that inherits it, under the rules of `REQ-SPEC-*` for the
   deriving contract.
9. REQ-NEXT-SOL-011. WHERE a base is an `interface` or a `library`, which
   have no state, THE Solidity_Translator SHALL NOT take invariants from it.

#### Acceptance Criteria — `super`

10. REQ-NEXT-SOL-012. THE Solidity_Translator SHALL resolve `super.f(...)`
    to the implementation of `f` declared by the contract that follows, in
    the C3 linearization, the contract in which the call is written — not
    the contract being verified. The linearization is the reverse of the
    order in REQ-NEXT-SOL-002.
11. REQ-NEXT-SOL-013. THE Solidity_Translator SHALL emit each
    implementation a `super` call reaches as an internal procedure of the
    deriving contract, named `__base_<DeclaringContract>_<function>`, and
    SHALL emit such procedures only for a file that uses `super`.
12. REQ-NEXT-SOL-014. IF `super.f(...)` has no inherited implementation of
    `f` to call, THEN THE Solidity_Translator SHALL fail with an
    `unsupported` error naming `f`.

#### Acceptance Criteria — Constructors

13. REQ-NEXT-SOL-015. THE Solidity_Translator SHALL run the statements of
    each inherited constructor before the deriving contract's own
    constructor body, in the order of REQ-NEXT-SOL-002, and after every
    state-variable initializer (`REQ-SPEC-*` constructor rules otherwise
    unchanged).
14. REQ-NEXT-SOL-016. IF an inherited constructor declares parameters,
    THEN THE Solidity_Translator SHALL NOT run it, SHALL emit a warning
    naming the base contract, and SHALL leave the state it would set at its
    default value. Root cause: the `Base(args)` clause that binds those
    arguments is not modelled. This is the remaining part of `GAP-009`.

#### Acceptance Criteria — Reporting

15. REQ-NEXT-SOL-017. IF a contract names a base that the verified file
    does not define (an imported one), THEN THE Solidity_Translator SHALL
    emit a warning naming the base and the deriving contract, and SHALL
    verify the contract without that base's members.
16. REQ-NEXT-SOL-018. THE Solidity_Translator SHALL emit the warnings of
    `REQ-OUT-*` and `REQ-SPEC-*` for a contract's own declarations only, so
    that an inherited declaration is reported once, against the contract
    that declares it.

#### Acceptance Criteria — Overloads

17. REQ-NEXT-SOL-019. Note. Overriding is resolved by function name, not by
    signature, because a procedure's name does not carry its parameter
    types either (unchanged from the baseline, where overloads within one
    contract already collide). Two inherited functions that differ only in
    their parameter types are therefore not distinguished.

#### Characterization

18. REQ-NEXT-TEST-001. THE Golden_Harness SHALL cover: inherited state,
    inherited internal calls, inherited modifiers, inherited invariants and
    an inherited constructor (`test/examples/inheritance.sol`); a `super`
    chain whose every postcondition is proven
    (`test/examples/inheritance_super.sol`); C3 order through a diamond
    (`test/examples/inheritance_diamond.sol`); and the two reported gaps
    (`test/examples/inheritance_gaps.sol`).
