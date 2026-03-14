#!/usr/bin/env python3
"""
strata-coverage: Specification coverage analysis for Solidity contracts.

Validates @custom:strata NatSpec annotations against the contract AST.
Reports unspecified functions, uncovered state variables, stale identifier
references, and modifies violations. Outputs plain text, JSON, or SARIF.

Usage:
    python3 -m src.strata_coverage contract.sol
    python3 -m src.strata_coverage contract.sol --json
    python3 -m src.strata_coverage contract.sol --sarif
"""

import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# solc invocation
# ---------------------------------------------------------------------------

def get_ast(sol_path: str) -> dict:
    source = Path(sol_path).read_text()
    input_json = json.dumps({
        "language": "Solidity",
        "sources": {sol_path: {"content": source}},
        "settings": {"outputSelection": {"*": {"": ["ast"]}}}
    })
    result = subprocess.run(
        ["solc", "--standard-json"],
        input=input_json, capture_output=True, text=True
    )
    output = json.loads(result.stdout)
    if "errors" in output:
        for e in output["errors"]:
            if e.get("severity") == "error":
                print(f"solc error: {e['message']}", file=sys.stderr)
                sys.exit(1)
    for src_name, src_data in output.get("sources", {}).items():
        return src_data["ast"]
    return {}


# ---------------------------------------------------------------------------
# AST walking helpers
# ---------------------------------------------------------------------------

def find_nodes(ast: dict, node_type: str):
    results = []
    if isinstance(ast, dict):
        if ast.get("nodeType") == node_type:
            results.append(ast)
        for v in ast.values():
            results.extend(find_nodes(v, node_type))
    elif isinstance(ast, list):
        for item in ast:
            results.extend(find_nodes(item, node_type))
    return results


def find_writes(body: dict) -> list:
    """Find all state variable assignment targets in a function body."""
    writes = []
    if body is None:
        return writes
    for assign in find_nodes(body, "Assignment"):
        lhs = assign.get("leftHandSide", {})
        name = _extract_write_target(lhs)
        if name:
            writes.append({"name": name, "line": assign.get("src", "").split(":")[0]})
    # Also catch += -= etc via operator
    for expr in find_nodes(body, "UnaryOperation"):
        if expr.get("operator") in ("++", "--"):
            name = _extract_write_target(expr.get("subExpression", {}))
            if name:
                writes.append({"name": name, "line": expr.get("src", "").split(":")[0]})
    return writes


def _extract_write_target(node: dict) -> Optional[str]:
    nt = node.get("nodeType")
    if nt == "Identifier":
        return node.get("name")
    if nt == "IndexAccess":
        base = node.get("baseExpression", {})
        return _extract_write_target(base)
    if nt == "MemberAccess":
        return node.get("memberName")
    return None


# ---------------------------------------------------------------------------
# NatSpec parsing
# ---------------------------------------------------------------------------

@dataclass
class StrataSpec:
    kind: str          # requires, ensures, invariant, modifies, loop-invariant
    expr: str          # raw expression string
    line: int = 0      # source line (approximate)


def parse_strata_specs(doc_text: str, base_line: int = 0) -> list:
    specs = []
    if not doc_text:
        return specs
    for i, line in enumerate(doc_text.split("\n")):
        line = line.strip()
        m = re.match(r"@custom:strata\s+(\S+)\s+(.*)", line)
        if m:
            specs.append(StrataSpec(kind=m.group(1), expr=m.group(2).strip(),
                                    line=base_line + i))
    return specs


def extract_identifiers(expr: str) -> set:
    """Extract all bare identifiers from a spec expression string."""
    # Remove type(...).min/max patterns first
    cleaned = re.sub(r'type\s*\([^)]+\)\s*\.\s*\w+', '', expr)
    # Remove old(...) wrapper but keep inner
    cleaned = re.sub(r'old\s*\(', '(', cleaned)
    tokens = re.findall(r'[a-zA-Z_][a-zA-Z0-9_]*', cleaned)
    keywords = {"old", "forall", "exists", "true", "false", "msg", "block",
                "tx", "type", "address", "uint256", "uint8", "int256", "bool",
                "sender", "value", "number", "timestamp", "min", "max"}
    return {t for t in tokens if t not in keywords}


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------

@dataclass
class Issue:
    rule_id: str
    message: str
    file: str
    line: int
    severity: str = "warning"  # warning or note


@dataclass
class CoverageReport:
    file: str
    contract: str = ""
    total_functions: int = 0
    specified_functions: int = 0
    total_state_vars: int = 0
    covered_state_vars: int = 0
    issues: list = field(default_factory=list)

    @property
    def score(self) -> float:
        total = self.total_functions + self.total_state_vars
        covered = self.specified_functions + self.covered_state_vars
        return covered / total if total > 0 else 1.0


def analyze(sol_path: str) -> CoverageReport:
    ast = get_ast(sol_path)
    report = CoverageReport(file=sol_path)
    source_text = Path(sol_path).read_text()
    source_lines = source_text.split("\n")

    for contract in find_nodes(ast, "ContractDefinition"):
        report.contract = contract.get("name", "")
        kind = contract.get("contractKind", "contract")
        if kind == "interface":
            continue

        # Collect state variables
        state_vars = {}
        for vd in contract.get("nodes", []):
            if vd.get("nodeType") == "VariableDeclaration" and vd.get("stateVariable"):
                name = vd.get("name")
                src = vd.get("src", "0:0:0")
                byte_offset = int(src.split(":")[0])
                line = source_text[:byte_offset].count("\n") + 1
                state_vars[name] = {"line": line, "has_ensures": False, "written_in": []}
        report.total_state_vars = len(state_vars)

        # Contract-level specs
        contract_doc = contract.get("documentation", {})
        contract_doc_text = contract_doc.get("text", "") if isinstance(contract_doc, dict) else (contract_doc or "")
        contract_specs = parse_strata_specs(contract_doc_text)
        has_invariant = any(s.kind == "invariant" for s in contract_specs)

        # Validate contract-level spec identifiers
        all_names = set(state_vars.keys())
        for spec in contract_specs:
            refs = extract_identifiers(spec.expr)
            for ref in refs:
                if ref not in all_names and ref not in {"sender", "value"}:
                    report.issues.append(Issue(
                        rule_id="strata/stale-reference",
                        message=f"@custom:strata {spec.kind} references '{ref}' — not a state variable",
                        file=sol_path, line=spec.line
                    ))

        # Analyze functions
        for fn in find_nodes(contract, "FunctionDefinition"):
            fn_name = fn.get("name") or fn.get("kind", "")
            fn_kind = fn.get("kind", "function")
            if fn_kind in ("constructor",):
                continue

            src = fn.get("src", "0:0:0")
            byte_offset = int(src.split(":")[0])
            fn_line = source_text[:byte_offset].count("\n") + 1

            report.total_functions += 1

            # Parse function NatSpec
            fn_doc = fn.get("documentation", {})
            fn_doc_text = fn_doc.get("text", "") if isinstance(fn_doc, dict) else (fn_doc or "")
            fn_specs = parse_strata_specs(fn_doc_text, fn_line)

            has_requires = any(s.kind == "requires" for s in fn_specs)
            has_ensures = any(s.kind == "ensures" for s in fn_specs)
            has_modifies = any(s.kind == "modifies" for s in fn_specs)

            if has_requires or has_ensures:
                report.specified_functions += 1
            else:
                if fn_kind == "function" and fn.get("visibility") in ("public", "external"):
                    report.issues.append(Issue(
                        rule_id="strata/unspecified-function",
                        message=f"Function '{fn_name}' has no @custom:strata specs",
                        file=sol_path, line=fn_line
                    ))

            # Collect parameter names for identifier validation
            param_names = set()
            for param_list in [fn.get("parameters", {}), fn.get("returnParameters", {})]:
                for p in param_list.get("parameters", []):
                    if p.get("name"):
                        param_names.add(p["name"])

            valid_names = all_names | param_names | {"msg", "sender", "value", "amount"}

            # Validate spec identifiers against AST
            for spec in fn_specs:
                if spec.kind in ("requires", "ensures", "loop-invariant"):
                    refs = extract_identifiers(spec.expr)
                    for ref in refs:
                        if ref not in valid_names:
                            report.issues.append(Issue(
                                rule_id="strata/stale-reference",
                                message=f"@custom:strata {spec.kind} references '{ref}' — "
                                        f"not a parameter or state variable of '{fn_name}'",
                                file=sol_path, line=spec.line
                            ))

            # Check modifies against actual writes
            modifies_vars = set()
            for spec in fn_specs:
                if spec.kind == "modifies":
                    for v in spec.expr.split(","):
                        v = v.strip()
                        # Strip index access: balances[to] -> balances
                        base = re.match(r'([a-zA-Z_]\w*)', v)
                        if base:
                            modifies_vars.add(base.group(1))

            body = fn.get("body")
            writes = find_writes(body) if body else []
            # Count writes per state variable
            write_counts = {}
            for w in writes:
                wname = w["name"]
                if wname in state_vars:
                    write_counts[wname] = write_counts.get(wname, 0) + 1
                    state_vars[wname]["written_in"].append(fn_name)
                    for spec in fn_specs:
                        if spec.kind == "ensures" and wname in extract_identifiers(spec.expr):
                            state_vars[wname]["has_ensures"] = True

                    if has_modifies and wname not in modifies_vars:
                        report.issues.append(Issue(
                            rule_id="strata/modifies-violation",
                            message=f"'{fn_name}' writes to '{wname}' but it's not in @custom:strata modifies",
                            file=sol_path, line=fn_line
                        ))

            # Check for suspicious multiple writes to same mapping
            if has_modifies:
                for vname, count in write_counts.items():
                    if count > 1 and vname in modifies_vars:
                        report.issues.append(Issue(
                            rule_id="strata/suspicious-write",
                            message=f"'{fn_name}' writes to '{vname}' {count} times "
                                    f"but modifies only declares one access pattern — "
                                    f"possible undeclared key write",
                            file=sol_path, line=fn_line,
                            severity="warning"
                        ))

        # Check state variable coverage
        for name, info in state_vars.items():
            if info["has_ensures"]:
                report.covered_state_vars += 1
            else:
                report.issues.append(Issue(
                    rule_id="strata/uncovered-state-var",
                    message=f"State variable '{name}' has no @custom:strata ensures covering it"
                            + (f" (written in {', '.join(info['written_in'])})" if info["written_in"] else ""),
                    file=sol_path, line=info["line"]
                ))

        if not has_invariant and state_vars:
            report.issues.append(Issue(
                rule_id="strata/no-invariant",
                message=f"Contract '{report.contract}' has state variables but no @custom:strata invariant",
                file=sol_path, line=1
            ))

    return report


# ---------------------------------------------------------------------------
# Output formatters
# ---------------------------------------------------------------------------

def format_plain(report: CoverageReport) -> str:
    lines = [f"=== Specification Coverage: {report.contract} ===", ""]
    lines.append(f"Functions: {report.specified_functions}/{report.total_functions} specified")
    lines.append(f"State vars: {report.covered_state_vars}/{report.total_state_vars} covered")
    lines.append(f"Score: {report.score:.0%}")
    lines.append("")
    if report.issues:
        lines.append(f"Issues ({len(report.issues)}):")
        for issue in report.issues:
            lines.append(f"  ⚠️  line {issue.line}: [{issue.rule_id}] {issue.message}")
    else:
        lines.append("No issues found ✅")
    return "\n".join(lines)


def format_json(report: CoverageReport) -> str:
    return json.dumps({
        "contract": report.contract,
        "score": round(report.score, 2),
        "functions": {"specified": report.specified_functions, "total": report.total_functions},
        "stateVars": {"covered": report.covered_state_vars, "total": report.total_state_vars},
        "issues": [{"ruleId": i.rule_id, "message": i.message, "line": i.line}
                   for i in report.issues]
    }, indent=2)


def format_sarif(report: CoverageReport) -> str:
    rules = [
        {"id": "strata/unspecified-function", "shortDescription": {"text": "Function has no verification specs"}},
        {"id": "strata/uncovered-state-var", "shortDescription": {"text": "State variable has no ensures covering writes"}},
        {"id": "strata/stale-reference", "shortDescription": {"text": "Spec references unknown identifier"}},
        {"id": "strata/modifies-violation", "shortDescription": {"text": "Write not declared in modifies annotation"}},
        {"id": "strata/no-invariant", "shortDescription": {"text": "Contract has no invariant annotation"}},
        {"id": "strata/suspicious-write", "shortDescription": {"text": "Multiple writes to same variable may indicate undeclared key access"}},
    ]
    rule_ids = [r["id"] for r in rules]
    results = []
    for issue in report.issues:
        idx = rule_ids.index(issue.rule_id) if issue.rule_id in rule_ids else 0
        results.append({
            "ruleId": issue.rule_id,
            "ruleIndex": idx,
            "level": issue.severity,
            "kind": "review",
            "message": {"text": issue.message},
            "locations": [{
                "physicalLocation": {
                    "artifactLocation": {"uri": report.file},
                    "region": {"startLine": max(issue.line, 1)}
                }
            }]
        })
    sarif = {
        "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json",
        "version": "2.1.0",
        "runs": [{
            "tool": {"driver": {"name": "strata-coverage", "version": "0.1.0", "rules": rules}},
            "results": results
        }]
    }
    return json.dumps(sarif, indent=2)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 2:
        print("Usage: strata-coverage <file.sol> [--json|--sarif]", file=sys.stderr)
        sys.exit(1)

    sol_path = sys.argv[1]
    fmt = "plain"
    if "--json" in sys.argv:
        fmt = "json"
    elif "--sarif" in sys.argv:
        fmt = "sarif"

    report = analyze(sol_path)

    if fmt == "json":
        print(format_json(report))
    elif fmt == "sarif":
        print(format_sarif(report))
    else:
        print(format_plain(report))

    sys.exit(1 if report.issues else 0)


if __name__ == "__main__":
    main()
