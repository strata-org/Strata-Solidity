#!/usr/bin/env python3
"""Run the real strataSolidity binary on every example and save its output.

Output lands next to each example as <name>.out (plain text, stdout).
build.py embeds it, so the site never shows invented output.

Usage (run from the repository root, after `lake build`):
    python3 docs/site/_src/capture_outputs.py
"""
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SCRIPT = REPO / "Tools/Solidity/scripts/strata-verify.sh"


def run(sol: Path, *flags: str):
    return subprocess.run([str(SCRIPT), str(sol), *flags], capture_output=True, text=True, timeout=600)


def main():
    commit = subprocess.run(["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    meta = {"commit": commit, "examples": {}}
    for sol in sorted((HERE / "examples").glob("*.sol")):
        text = run(sol)
        (sol.with_suffix(".out")).write_text(text.stdout.strip() + "\n")
        summary = next((l for l in text.stdout.splitlines() if " passed, " in l), "")
        meta["examples"][sol.name] = {"exit_code": text.returncode, "summary": summary}
        print(f"{sol.name:<28} exit {text.returncode}  {summary}")
    (HERE / "examples" / "outputs.json").write_text(json.dumps(meta, indent=2) + "\n")


if __name__ == "__main__":
    main()
