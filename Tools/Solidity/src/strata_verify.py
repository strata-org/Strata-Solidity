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
import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
TOOLS_DIR = SCRIPT_DIR.parent
PROJECT_DIR = TOOLS_DIR.parent.parent
DIALECT = TOOLS_DIR / "dialects" / "Solidity.dialect.st.ion"
STRATA_BIN = PROJECT_DIR / ".lake" / "build" / "bin" / "strataSolidity"


def verify_file(sol_path: str, sarif: bool = False, timeout: int = 0) -> dict:
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


def main():
    # Mode 1: --file <path.sol>
    if "--file" in sys.argv:
        idx = sys.argv.index("--file")
        sol_path = sys.argv[idx + 1]
        sarif = "--sarif" in sys.argv
        result = verify_file(sol_path, sarif=sarif)
        print(json.dumps(result, indent=2))
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

    timeout = (input_json.get("settings", {})
               .get("modelChecker", {}).get("timeout", 0))
    sarif = "--sarif" in sys.argv

    sources = input_json.get("sources", {})
    all_errors = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for filename, source_info in sources.items():
            sol_path = os.path.join(tmpdir, filename)
            os.makedirs(os.path.dirname(sol_path), exist_ok=True)
            content = source_info.get("content", "")
            Path(sol_path).write_text(content)
            result = verify_file(sol_path, sarif=sarif, timeout=timeout)
            all_errors.extend(result.get("errors", []))

    print(json.dumps({"errors": all_errors}, indent=2))


if __name__ == "__main__":
    main()
