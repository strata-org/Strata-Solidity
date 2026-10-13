# Copyright Strata Contributors
#
#  SPDX-License-Identifier: Apache-2.0 OR MIT

"""Schema-compliance test for ``strata-verify.sh --sarif``.

Realizes REQ-PBT-004 (design §13.4): runs ``strata-verify.sh --sarif`` against
one or more fixtures and validates the stdout payload against the SARIF 2.1.0
JSON schema using :mod:`jsonschema`.

Validates: REQ-PBT-004, REQ-OUT-030, REQ-OUT-031.

This test is a characterization check — it pins the current binary's output
format against the published schema so ``strata-solidity-next`` cannot break
SARIF compliance unnoticed. The schema is vendored under
``Tools/Solidity/test/schemas/sarif-schema-2.1.0.json`` (see that file's header
comment for provenance); vendoring avoids network dependencies during CI runs.

The test is skipped (not silently passed) when the Lean binary has not been
built yet, so a missing ``.lake/build/bin/strataSolidity`` is surfaced
explicitly rather than masked.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

try:
    import jsonschema
except ImportError as exc:  # pragma: no cover - import-time guard only
    raise RuntimeError(
        "jsonschema is required; install via "
        "`pip install -r Tools/Solidity/requirements-dev.txt`"
    ) from exc


# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------

# This file lives at <repo>/Tools/Solidity/test/test_sarif_schema.py, so the
# repository root is three parents up.
_THIS_DIR = Path(__file__).resolve().parent
_PROJECT_ROOT = _THIS_DIR.parents[2]

_STRATA_VERIFY = _PROJECT_ROOT / "Tools" / "Solidity" / "scripts" / "strata-verify.sh"
_STRATA_BIN = _PROJECT_ROOT / ".lake" / "build" / "bin" / "strataSolidity"
# Dialect is compiled into the binary (Lean-canonical); no Ion artifact needed.
_SCHEMA_PATH = _THIS_DIR / "schemas" / "sarif-schema-2.1.0.json"

# Fixtures are curated to exercise at least one @custom:strata spec or
# assertion so the SARIF ``results[]`` array is non-empty. Paths are relative
# to the repository root.
_FIXTURES = [
    Path("StrataSolidityTest") / "Solidity" / "tests" / "test_require_assert.sol",
    Path("test") / "examples" / "b1_trivial.sol",
    # Has failing obligations, so counterexample-bearing results are covered.
    Path("StrataSolidityTest") / "Solidity" / "tests" / "test_spec_failures.sol",
    # Carries `strata/not-verified` results for ignored annotations.
    Path("test") / "examples" / "ignored_annotations.sol",
]


# ---------------------------------------------------------------------------
# Skip guards
# ---------------------------------------------------------------------------

def _require_built_binary() -> None:
    if not _STRATA_BIN.exists():
        pytest.skip(
            f"strataSolidity binary not found at {_STRATA_BIN}; "
            "run `lake build` in the repository root before running this test."
        )


def _require_dialect() -> None:
    """Dialect is Lean-canonical and compiled into the binary; nothing to check."""
    return


def _require_solc() -> None:
    if shutil.which("solc") is None:
        pytest.skip("solc is not on PATH; strata-verify.sh cannot parse fixtures.")


# ---------------------------------------------------------------------------
# Schema loader (cached at module level)
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def sarif_schema() -> dict:
    """Load the vendored SARIF 2.1.0 JSON schema."""
    assert _SCHEMA_PATH.is_file(), (
        f"vendored SARIF schema missing at {_SCHEMA_PATH}; "
        "restore it from the OASIS SARIF 2.1.0 committee specification."
    )
    with _SCHEMA_PATH.open("r", encoding="utf-8") as fh:
        return json.load(fh)


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def _run_sarif(fixture: Path) -> dict:
    """Run strata-verify.sh --sarif on *fixture* and return parsed JSON."""
    fixture_abs = (_PROJECT_ROOT / fixture).resolve()
    assert fixture_abs.is_file(), f"fixture not found: {fixture_abs}"

    env = os.environ.copy()
    # Ensure deterministic behavior: no locale-dependent rendering.
    env.setdefault("LC_ALL", "C")

    completed = subprocess.run(
        ["bash", str(_STRATA_VERIFY), str(fixture_abs), "--sarif"],
        capture_output=True,
        text=True,
        cwd=str(_PROJECT_ROOT),
        env=env,
        check=False,
    )

    # strata-verify.sh may return non-zero when the fixture has failing
    # obligations; that is expected and does not invalidate the SARIF payload.
    # We only fail the test if stdout is not a valid SARIF document.
    stdout = completed.stdout
    assert stdout.strip(), (
        "strata-verify.sh --sarif produced empty stdout for "
        f"{fixture} (exit={completed.returncode}); stderr:\n{completed.stderr}"
    )

    try:
        return json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise AssertionError(
            "strata-verify.sh --sarif stdout is not valid JSON for "
            f"{fixture}: {exc}\n--- stdout ---\n{stdout}\n--- stderr ---\n"
            f"{completed.stderr}"
        ) from exc


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("fixture", _FIXTURES, ids=lambda p: p.name)
def test_sarif_output_validates_against_schema(
    fixture: Path, sarif_schema: dict
) -> None:
    """``strata-verify.sh --sarif`` stdout must validate against SARIF 2.1.0.

    Validates: REQ-PBT-004, REQ-OUT-030, REQ-OUT-031.
    """
    _require_built_binary()
    _require_dialect()
    _require_solc()

    payload = _run_sarif(fixture)

    # Minimal structural sanity before handing to jsonschema, so a malformed
    # payload produces a more actionable failure than a raw schema error.
    assert payload.get("version") == "2.1.0", (
        f"expected SARIF version 2.1.0; got {payload.get('version')!r}"
    )
    assert isinstance(payload.get("runs"), list) and payload["runs"], (
        "SARIF payload missing non-empty 'runs' array"
    )

    # Will raise jsonschema.ValidationError on any schema violation.
    jsonschema.validate(instance=payload, schema=sarif_schema)


def _results(payload: dict) -> list[dict]:
    return payload["runs"][0]["results"]


def test_sarif_rule_index_points_at_rule_id() -> None:
    """Every result's ``ruleIndex`` must name the rule its ``ruleId`` names."""
    _require_built_binary()
    _require_solc()
    payload = _run_sarif(Path("StrataSolidityTest") / "Solidity" / "tests" / "test_spec_failures.sol")
    rules = payload["runs"][0]["tool"]["driver"]["rules"]
    for r in _results(payload):
        assert rules[r["ruleIndex"]]["id"] == r["ruleId"], r


def test_sarif_verdicts_agree_with_cli() -> None:
    """Proven obligations are ``pass``, refuted ones ``fail``.

    SARIF used to require a reachability check that is not run by default,
    so every proven obligation was reported as ``open`` (unknown).
    """
    _require_built_binary()
    _require_solc()

    trivial = _results(_run_sarif(Path("test") / "examples" / "b1_trivial.sol"))
    assert trivial and all(r["kind"] == "pass" for r in trivial), trivial
    assert {r["ruleId"] for r in trivial} == {"strata/ensures-fail", "strata/frame-fail"}

    failing = _results(_run_sarif(
        Path("StrataSolidityTest") / "Solidity" / "tests" / "test_spec_failures.sol"))
    failed = {(r["ruleId"], r["message"]["text"]) for r in failing if r["kind"] == "fail"}
    assert ("strata/ensures-fail", "ensures res == a + b + 1: fail") in failed, failed
    assert ("strata/invariant-fail", "invariant counter <= 100: fail") in failed, failed


def test_sarif_reports_unverified_annotations() -> None:
    """Every warning the CLI prints appears as a ``strata/not-verified`` result."""
    _require_built_binary()
    _require_solc()
    fixture = Path("test") / "examples" / "ignored_annotations.sol"
    payload = _run_sarif(fixture)
    unverified = [r for r in _results(payload) if r["ruleId"] == "strata/not-verified"]
    text = subprocess.run(
        ["bash", str(_STRATA_VERIFY), str((_PROJECT_ROOT / fixture).resolve())],
        capture_output=True, text=True, cwd=str(_PROJECT_ROOT), check=False)
    warnings = [l for l in text.stderr.splitlines() if ": warning: " in l]
    assert warnings and len(unverified) == len(warnings), (unverified, warnings)
    assert all(r["kind"] == "fail" and r["level"] == "warning" and r["locations"]
               for r in unverified), unverified


@pytest.mark.parametrize("fixture", _FIXTURES, ids=lambda p: p.name)
def test_sarif_prose_rules(fixture: Path) -> None:
    """Rules of SARIF 2.1.0 that its JSON schema cannot express.

    - §3.27.10: if `kind` is not "fail", `level` is absent or "none".
    - §3.14.27: a run with results over text artifacts has `columnKind`.
    - Code scanning needs at least one location to display a result.
    """
    _require_built_binary()
    _require_solc()
    payload = _run_sarif(fixture)
    run = payload["runs"][0]
    assert run.get("columnKind") == "unicodeCodePoints", run.keys()
    for r in run["results"]:
        if r.get("kind", "fail") != "fail":
            assert r.get("level", "none") == "none", r
        assert r.get("locations"), r


def _json_statuses(fixture: Path, *extra: str) -> list[str]:
    completed = subprocess.run(
        [str(_STRATA_BIN), str((_PROJECT_ROOT / fixture).resolve()), "--json", *extra],
        capture_output=True, text=True, cwd=str(_PROJECT_ROOT), check=False)
    return [r["status"] for r in json.loads(completed.stdout)]


def test_sarif_matches_json_per_obligation() -> None:
    """Each obligation, and each annotation or function that is not
    verified, has the same verdict in SARIF and in --json."""
    _require_built_binary()
    _require_solc()
    expected = {"pass": ("pass", "none"), "fail": ("fail", "error"),
                "unknown": ("fail", "warning"), "implementation_error": ("fail", "error"),
                "not_verified": ("fail", "warning")}
    for fixture in _FIXTURES:
        statuses = _json_statuses(fixture)
        results = _results(_run_sarif(fixture))
        assert [(r["kind"], r["level"]) for r in results] == \
            [expected[st] for st in statuses], (fixture, statuses)
        assert sum(r["ruleId"] == "strata/not-verified" for r in results) == \
            statuses.count("not_verified"), fixture



_FP_V1 = """// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
contract FP {
    function a(uint256 x) external pure { assert(x > 5); }
    function b(uint256 x) external pure { assert(x >= 0); }
}
"""
# The same contract with a function, and a failing assert, inserted above.
_FP_V2 = _FP_V1.replace(
    "contract FP {\n",
    "contract FP {\n    function n(uint256 x) external pure { assert(x > 9); }\n")


def test_sarif_fingerprints_survive_unrelated_edits(tmp_path: Path) -> None:
    """An unchanged obligation keeps its fingerprint when code is inserted
    above it, and a new obligation does not take an old one's."""
    _require_built_binary()
    _require_solc()

    def fingerprints(source: str, name: str) -> dict[int, str]:
        path = tmp_path / name
        path.write_text(source)
        results = _results(_run_sarif(path))
        return {r["locations"][0]["physicalLocation"]["region"]["startLine"]:
                r["partialFingerprints"]["obligationId/v2"] for r in results}

    v1 = fingerprints(_FP_V1, "v1.sol")
    v2 = fingerprints(_FP_V2, "v2.sol")
    # a and b moved down one line; n's assert is new.
    assert v2[5] == v1[4] and v2[6] == v1[5], (v1, v2)
    assert v2[4] not in v1.values(), (v1, v2)
