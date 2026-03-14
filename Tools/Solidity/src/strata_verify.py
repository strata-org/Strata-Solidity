#!/usr/bin/env python3
"""
strata-verify: solc-compatible standard-json wrapper for Strata verification.

Accepts solc standard-json input on stdin with settings.modelChecker.engine = "strata".
Runs the Strata verification pipeline and returns results in solc-compatible JSON format.

Usage:
    echo '{"language":"Solidity","sources":{"file.sol":{"content":"..."}},"settings":{"modelChecker":{"engine":"strata"}}}' | python3 -m src.strata_verify
    python3 -m src.strata_verify --file contract.sol
"""

import json
import logging
import os
import subprocess
import sys
import tempfile
from pathlib import Path

logger = logging.getLogger(__name__)

SCRIPT_DIR = Path(__file__).resolve().parent
TOOLS_DIR = SCRIPT_DIR.parent
PROJECT_DIR = TOOLS_DIR.parent.parent
DIALECT = TOOLS_DIR / "dialects" / "Solidity.dialect.st.ion"
STRATA_BIN = PROJECT_DIR / ".lake" / "build" / "bin" / "strataSolidity"


def verify_file(sol_path: str, sarif: bool = False, timeout: int = 0,
                solver: str = "z3") -> dict:
    """Run the Strata pipeline on a .sol file, return solc-compatible JSON."""
    with tempfile.TemporaryDirectory() as tmpdir:
        ion_path = os.path.join(tmpdir, Path(sol_path).stem + ".solidity.st.ion")

        # Step 1: sol -> Ion
        env = os.environ.copy()
        strata_python = str(PROJECT_DIR.parent / "Strata" / "Tools" / "Python")
        env["PYTHONPATH"] = strata_python + ":" + env.get("PYTHONPATH", "")

        try:
            subprocess.run(
                [sys.executable, "-m", "src.solast", "sol_to_strata",
                 "--dialect", str(DIALECT), sol_path, ion_path],
                cwd=str(TOOLS_DIR),
                env=env, check=True, capture_output=True, text=True,
            )
        except subprocess.CalledProcessError as e:
            return {"errors": [{"severity": "error", "message": f"Parse failed: {e.stderr}"}]}

        # Step 2: Ion -> verify
        cmd = [str(STRATA_BIN), ion_path]
        if sarif:
            cmd.append("--sarif")

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=False,
                                    timeout=timeout if timeout > 0 else None)
        except subprocess.TimeoutExpired:
            return {"errors": [{"severity": "warning", "message": "Verification timed out"}]}

        if result.returncode != 0 and not result.stdout:
            return {"errors": [{"severity": "error", "message": result.stderr.strip()}]}

        # Parse verification output into solc-compatible errors array
        if sarif:
            return json.loads(result.stdout) if result.stdout else {}

        errors = []
        for line in result.stdout.splitlines():
            line = line.strip()
            if not line or line.startswith("===="):
                continue
            if "✅ pass" in line:
                errors.append({"severity": "warning", "type": "Info",
                               "message": f"Strata: {line}"})
            elif "❌ fail" in line:
                errors.append({"severity": "error",
                               "message": f"Strata: {line}"})
            elif "🟡 unknown" in line:
                errors.append({"severity": "warning",
                               "message": f"Strata: {line}"})
        return {"errors": errors}


def _parse_model_checker(mc: dict) -> dict:
    """Extract and validate modelChecker settings, return normalized config."""
    cfg = {"engine": mc.get("engine", "strata"), "timeout": mc.get("timeout", 0)}

    targets = mc.get("targets")
    if targets:
        cfg["targets"] = targets

    contracts = mc.get("contracts")
    if contracts:
        cfg["contracts"] = contracts
        logger.warning("settings.modelChecker.contracts filtering is not yet supported; all contracts will be verified")

    solvers = mc.get("solvers")
    solver = "z3"
    if solvers:
        cfg["solvers"] = solvers
        solver = solvers[0]
        if solver != "z3":
            logger.warning("Solver '%s' requested; defaulting to z3 (only z3 currently supported)", solver)
            solver = "z3"
    cfg["_solver"] = solver
    return cfg


def main():
    # Parse --fail-under N
    fail_under = None
    if "--fail-under" in sys.argv:
        idx = sys.argv.index("--fail-under")
        fail_under = float(sys.argv[idx + 1])
        del sys.argv[idx:idx + 2]

    # Mode 1: --file <path.sol>
    if "--file" in sys.argv:
        idx = sys.argv.index("--file")
        sol_path = sys.argv[idx + 1]
        sarif = "--sarif" in sys.argv
        result = verify_file(sol_path, sarif=sarif)
        print(json.dumps(result, indent=2))
        if fail_under is not None:
            _check_fail_under(sol_path, fail_under)
        return

    # Mode 2: standard-json on stdin
    try:
        input_json = json.load(sys.stdin)
    except json.JSONDecodeError:
        print(json.dumps({"errors": [{"severity": "error",
                                       "message": "Invalid JSON input"}]}))
        return

    engine = (input_json.get("settings", {})
              .get("modelChecker", {}).get("engine", "none"))
    if engine != "strata":
        print(json.dumps({"errors": [{"severity": "error",
                                       "message": f"Unsupported engine: {engine}. Use 'strata'."}]}))
        return

    mc = input_json.get("settings", {}).get("modelChecker", {})
    mc_cfg = _parse_model_checker(mc)
    timeout = mc_cfg["timeout"]
    solver = mc_cfg["_solver"]
    sarif = "--sarif" in sys.argv

    sources = input_json.get("sources", {})
    all_errors = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for filename, source_info in sources.items():
            sol_path = os.path.join(tmpdir, filename)
            os.makedirs(os.path.dirname(sol_path), exist_ok=True)
            content = source_info.get("content", "")
            Path(sol_path).write_text(content)
            result = verify_file(sol_path, sarif=sarif, timeout=timeout,
                                 solver=solver)
            all_errors.extend(result.get("errors", []))

    output = {"errors": all_errors}
    if "targets" in mc_cfg:
        output["modelCheckerTargets"] = mc_cfg["targets"]
    print(json.dumps(output, indent=2))


def _check_fail_under(sol_path: str, threshold: float):
    """Run coverage analysis and exit non-zero if score < threshold%."""
    from src.strata_coverage import analyze
    report = analyze(sol_path)
    pct = report.score * 100
    if pct < threshold:
        print(f"FAIL: coverage {pct:.1f}% < {threshold}%", file=sys.stderr)
        sys.exit(1)
    print(f"OK: coverage {pct:.1f}% >= {threshold}%", file=sys.stderr)


if __name__ == "__main__":
    main()
