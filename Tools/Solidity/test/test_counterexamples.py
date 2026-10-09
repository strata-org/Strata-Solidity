# Copyright Strata Contributors
#
#  SPDX-License-Identifier: Apache-2.0 OR MIT

"""Refuted obligations come with a counterexample.

The golden runner (`test/run_tests.sh`) compares only result counts, so a
change that drops counterexamples (for instance a model that Core's reader
cannot parse) would go unnoticed there. This test runs fixtures whose
failures must each print at least one `name = value` line.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest

_PROJECT_ROOT = Path(__file__).resolve().parents[3]
_STRATA_VERIFY = _PROJECT_ROOT / "Tools" / "Solidity" / "scripts" / "strata-verify.sh"
_STRATA_BIN = _PROJECT_ROOT / ".lake" / "build" / "bin" / "strataSolidity"

# Fixtures whose every failure has a counterexample.
_FIXTURES = [
    "test/examples/counterexample_models.sol",
]


def _failures(text: str) -> list[tuple[str, list[str]]]:
    """(obligation, counterexample lines) for each entry of the Failures section."""
    out: list[tuple[str, list[str]]] = []
    in_failures = False
    for line in text.splitlines():
        if re.match(r"^(✅|❌|❓|⚠️) ", line):
            in_failures = line.startswith("❌ Failures")
            continue
        if not in_failures or not line.strip():
            continue
        # An obligation is indented by two spaces; its counterexample lines
        # (`name = value`, possibly wrapped) by more.
        if re.match(r"^  \S", line) and " = " not in line and ":=" not in line:
            out.append((line.strip(), []))
        elif out:
            out[-1][1].append(line.strip())
    return out


@pytest.mark.skipif(not _STRATA_BIN.exists(), reason="strataSolidity binary not built")
@pytest.mark.parametrize("fixture", _FIXTURES)
def test_failures_have_counterexamples(fixture: str) -> None:
    proc = subprocess.run(
        ["bash", str(_STRATA_VERIFY), str(_PROJECT_ROOT / fixture), "--timeout=15"],
        capture_output=True, text=True, timeout=600,
    )
    failures = _failures(proc.stdout)
    assert failures, f"{fixture}: expected at least one failure\n{proc.stdout}"
    for name, model in failures:
        assert any(" = " in m for m in model), f"{fixture}: `{name}` has no counterexample"


_LOCATED = """// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
contract Loc {
    uint256 public cap = 1000;
    /// @custom:strata requires x > 10
    function helper(uint256 x) internal pure returns (uint256) { return x; }
    function viaInit(uint256 d) external pure returns (uint256) {
        uint256 a = helper(2);
        uint256 b = 10 / d;
        return a + b;
    }
    function viaReturn(uint256 d) external pure returns (uint256) {
        return helper(3) % d;
    }
    function frame() external { cap = 1; }
}
"""


@pytest.mark.skipif(not _STRATA_BIN.exists(), reason="strataSolidity binary not built")
def test_every_result_is_located(tmp_path: Path) -> None:
    """Checks lifted out of initializers and `return` expressions, and heap
    frames, are reported at a source line."""
    path = tmp_path / "loc.sol"
    path.write_text(_LOCATED)
    proc = subprocess.run([str(_STRATA_BIN), str(path)], capture_output=True, text=True, timeout=600)
    results = [l.strip() for l in proc.stdout.splitlines()
               if l.startswith("  ") and not l.startswith("        ")]
    assert len(results) == 5, proc.stdout
    unlocated = [r for r in results if " at line " not in r]
    assert not unlocated, unlocated
