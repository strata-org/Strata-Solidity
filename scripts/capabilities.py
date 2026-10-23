#!/usr/bin/env python3
# Copyright Strata Contributors
#
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""The capability ledger: what StrataSolidity verifies, partly verifies,
skips or rejects, with the tests that show it (docs/capabilities.toml).

The tables of supported and unsupported features in the documentation are
generated from the ledger, between `<!-- capabilities:begin VIEW -->` and
`<!-- capabilities:end VIEW -->` markers, and the landing page's lists are
rendered from it by docs/site/_src/build.py.

Usage:
  python3 scripts/capabilities.py           check the ledger, then rewrite
                                            the generated sections
  python3 scripts/capabilities.py --check   check the ledger, and fail if a
                                            generated section is out of date

The checks:
  - every witness holds in the golden files (test/expected/), which
    test/run_tests.sh compares with the binary's results: a `proven`
    witness names an obligation the fixture reports as proven (✅), an
    `error` witness text in its translation error, and so on;
  - the witnesses of an entry fit its status: a verified feature has a
    proven obligation and one that is refuted or not proven (or a test
    that checks it), a rejected one an error, a skipped one a warning;
  - a gap marked closed has only verified entries citing it, and an open
    or narrowed one has an entry that is not verified;
  - the options listed are the options StrataSolidityMain.lean reads, and
    the annotations listed are the keywords SpecParser.lean reads;
  - each generated section equals what the ledger renders.
"""
from __future__ import annotations

import argparse
import html
import os
import re
import sys
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LEDGER = REPO / "docs" / "capabilities.toml"
EXAMPLES = REPO / "test" / "examples"
EXPECTED = REPO / "test" / "expected"
GUIDE = REPO / "docs" / "guide" / "src"
MAIN = REPO / "StrataSolidityMain.lean"
SPEC_PARSER = REPO / "StrataSolidity" / "SolTranslator" / "SpecParser.lean"

# The files that contain generated sections.
TARGETS = [
    "LIMITATIONS.md",
    "README.md",
    "FAQ.md",
    "docs/guide/src/supported_features.md",
    "docs/guide/src/limitations.md",
    "docs/guide/src/first_verification.md",
    ".kiro/specs/strata-solidity-next/requirements.md",
]

# status: (icon, label, meaning)
STATUSES = {
    "verified": ("✅", "Verified",
                 "modelled as Solidity runs it. A true property can be proven; a "
                 "false one is refuted or not proven"),
    "partial": ("⚠️", "Partly",
                "modelled, except for what the notes say"),
    "unknown": ("⚠️", "Unknown values",
                "not interpreted. What it may change or return is unknown "
                "afterwards: a property that depends on it is not proven, and "
                "nothing false is proven either"),
    "skipped": ("⚠️", "Not verified",
                "skipped, with a warning. The rest of the file is verified"),
    "rejected": ("❌", "Rejected",
                 "the translation stops with an error that says why. Nothing in "
                 "the file is verified"),
    "fails": ("❌", "Fails",
              "valid Solidity on which the translation stops with an internal "
              "error. Nothing in the file is verified"),
}
SUPPORTED_VIEW = ("verified", "partial", "unknown")
LIMITATIONS_VIEW = ("partial", "unknown", "skipped", "rejected", "fails")

VERDICTS = {"proven": {"✅"}, "refuted": {"❌"}, "unknown": {"❓"},
            "not_proven": {"❌", "❓", "⚠", "⚠️"}}
POSITIVE = {"proven", "test", "source"}
NEGATIVE = {"refuted", "unknown", "not_proven"}
GAP_STATUSES = {"open", "narrowed", "closed", "obsolete"}

BEGIN = re.compile(r"<!-- capabilities:begin (?P<view>[\w-]+)(?P<args>[^>]*?)\s*-->\n")
NOTICE = ("<!-- Generated from docs/capabilities.toml by scripts/capabilities.py: "
          "edit the ledger, then run the script. -->")


class LedgerError(Exception):
    pass


def load() -> dict:
    with LEDGER.open("rb") as f:
        ledger = tomllib.load(f)
    ledger["areas"] = {a["id"]: a for a in ledger["area"]}
    ledger["gaps"] = {g["id"]: g for g in ledger.get("gap", [])}
    return ledger


# ---------------------------------------------------------------- checks

def golden(fixture: str) -> tuple[list[tuple[str, int, str]], list[str], list[str]]:
    """The obligations (verdict, line, description), translation errors and
    warnings that the golden files of `fixture` record."""
    expected = EXPECTED / f"{fixture}.expected"
    if not (EXAMPLES / f"{fixture}.sol").is_file():
        raise LedgerError(f"no fixture test/examples/{fixture}.sol")
    if not expected.is_file():
        raise LedgerError(f"no golden file test/expected/{fixture}.expected")
    obligations, errors = [], []
    for line in expected.read_text().splitlines():
        m = re.match(r"^(✅|❌|❓|⚠️?) (\d+): (.*)$", line)
        if m:
            obligations.append((m.group(1), int(m.group(2)), m.group(3)))
        elif re.match(r"^(Exception|uncaught exception|BUG): ", line):
            errors.append(line)
    warnings_file = EXPECTED / f"{fixture}.warnings"
    warnings = warnings_file.read_text().splitlines() if warnings_file.is_file() else []
    return obligations, errors, warnings


def witness_kind(w: dict) -> str:
    kinds = [k for k in ("proven", "refuted", "unknown", "not_proven", "error",
                         "warning", "test", "source") if k in w]
    if len(kinds) != 1:
        raise LedgerError(f"a witness needs exactly one kind, got {sorted(w)}")
    return kinds[0]


def check_witness(w: dict) -> str:
    """The witness's kind, if it holds; raises LedgerError otherwise."""
    kind = witness_kind(w)
    if kind in ("test", "source"):
        path = REPO / w[kind]
        if not path.is_file():
            raise LedgerError(f"no file {w[kind]}")
        if "contains" in w and w["contains"] not in path.read_text():
            raise LedgerError(f"{w[kind]} does not contain {w['contains']!r}")
        return kind
    fixture = w.get("fixture")
    if not fixture:
        raise LedgerError(f"a `{kind}` witness needs a fixture")
    obligations, errors, warnings = golden(fixture)
    text = w[kind]
    if kind in VERDICTS:
        if not any(v in VERDICTS[kind] and d == text and w.get("line", n) == n
                   for v, n, d in obligations):
            at = f" at line {w['line']}" if "line" in w else ""
            raise LedgerError(f"{fixture}: no obligation `{text}`{at} reported {kind}")
    elif kind == "error":
        if not any(text in e for e in errors):
            raise LedgerError(f"{fixture}: no translation error containing {text!r}")
    elif not any(text in x for x in warnings):
        raise LedgerError(f"{fixture}: no warning containing {text!r}")
    return kind


def check_shape(status: str, kinds: list[str]) -> str | None:
    """Why `kinds` does not show `status`, or None."""
    found = set(kinds)
    if status == "verified":
        if ("proven" in found and found & NEGATIVE) or found & {"test", "source"}:
            return None
        return "a verified entry needs a proven and a refuted or not-proven witness, or a test"
    if status == "partial":
        if len(kinds) >= 2 and found & POSITIVE:
            return None
        return "a partly supported entry needs two witnesses, one of them proven or a test"
    if status == "unknown":
        if "proven" in found and found & NEGATIVE:
            return None
        return "an unknown-values entry needs a proven and a not-proven witness"
    if status == "skipped":
        return None if "warning" in found else "a skipped entry needs a warning witness"
    return None if "error" in found else f"a {status} entry needs an error witness"


def flags_in_main() -> set[str]:
    src = MAIN.read_text()
    flags = set(re.findall(r'"(--[a-z][a-z-]*=?)"', src))
    env = set(re.findall(r'IO\.getEnv "([A-Z_]+)"', src))
    return flags | env


def flag_key(name: str) -> str:
    """`--timeout=<s>` → `--timeout=`; `STRATA_SMT_DIR=<dir>` → `STRATA_SMT_DIR`."""
    if name.startswith("--"):
        return name.split("=")[0] + ("=" if "=" in name else "")
    return name.split("=")[0]


def annotation_keywords() -> set[str]:
    return set(re.findall(r'\|\s*"([a-z-]+)"\s*=>\s*some\s*\(\.', SPEC_PARSER.read_text()))


def check(ledger: dict) -> list[str]:
    problems = []
    ids = set()
    for e in ledger["capability"]:
        where = f"capability `{e.get('id', '?')}`"
        for field in ("id", "area", "feature", "status", "notes", "witness"):
            if field not in e:
                problems.append(f"{where}: missing `{field}`")
        if e.get("id") in ids:
            problems.append(f"{where}: duplicate id")
        ids.add(e.get("id"))
        if e.get("area") not in ledger["areas"]:
            problems.append(f"{where}: unknown area {e.get('area')!r}")
        status = e.get("status")
        if status not in STATUSES:
            problems.append(f"{where}: unknown status {status!r}")
            continue
        if "gap" in e and e["gap"] not in ledger["gaps"]:
            problems.append(f"{where}: unknown gap {e['gap']}")
        if "works" in e and status not in ("verified", "partial"):
            problems.append(f"{where}: `works` highlight on a {status} entry")
        if "not_yet" in e and status == "verified":
            problems.append(f"{where}: `not_yet` highlight on a verified entry")
        for field in ("feature", "notes"):
            if "|" in e.get(field, ""):
                problems.append(f"{where}: `|` in {field} (it would split the table cell)")
        kinds = []
        for w in e.get("witness", []):
            try:
                kinds.append(check_witness(w))
            except LedgerError as err:
                problems.append(f"{where}: {err}")
        if len(kinds) == len(e.get("witness", [])):
            why = check_shape(status, kinds)
            if why:
                problems.append(f"{where}: {why}")

    for g in ledger["gaps"].values():
        citing = [e for e in ledger["capability"] if e.get("gap") == g["id"]]
        if g.get("status") not in GAP_STATUSES:
            problems.append(f"gap {g['id']}: unknown status {g.get('status')!r}")
        elif g["status"] == "closed" and (not citing or any(e["status"] != "verified" for e in citing)):
            problems.append(f"gap {g['id']} is closed, so it needs entries, all verified")
        elif g["status"] in ("open", "narrowed") and all(e["status"] == "verified" for e in citing):
            problems.append(f"gap {g['id']} is {g['status']}, so it needs an entry that is not verified")

    for kind in ("works", "not_yet"):
        order = ledger.get("highlights", {}).get(kind, [])
        having = [e["id"] for e in ledger["capability"] if kind in e]
        for i in sorted(set(order) ^ set(having)):
            side = "has no `%s` text" % kind if i in order else "is missing from [highlights]"
            problems.append(f"highlight `{i}` ({kind}): {side}")
        if len(order) != len(set(order)):
            problems.append(f"[highlights] {kind}: an id appears twice")

    listed = {flag_key(f["name"]) for f in ledger["flag"]}
    read = flags_in_main()
    for f in sorted(read - listed):
        problems.append(f"option {f}: read by StrataSolidityMain.lean, missing from the ledger")
    for f in sorted(listed - read):
        problems.append(f"option {f}: in the ledger, not read by StrataSolidityMain.lean")

    listed = {a["keyword"] for a in ledger["annotation"]}
    read = annotation_keywords()
    for k in sorted(read ^ listed):
        side = "missing from the ledger" if k in read else "not read by SpecParser.lean"
        problems.append(f"annotation `{k}`: {side}")
    return problems


# ---------------------------------------------------------------- rendering

def link(md: str, target: Path) -> str:
    """Resolve `](guide:page.md#anchor)` links relative to `target`."""
    def sub(m):
        rel = os.path.relpath(GUIDE / m.group(1), target.parent)
        if "/" not in rel:
            rel = "./" + rel
        return f"]({rel}{m.group(2) or ''})"
    return re.sub(r"\]\(guide:([\w-]+\.md)(#[\w-]+)?\)", sub, md)


def one_line(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def status_cell(status: str) -> str:
    icon, label, _ = STATUSES[status]
    return f"{icon} {label}"


def notes_cell(e: dict) -> str:
    notes = one_line(e["notes"])
    if "gap" in e and e["status"] != "verified":
        notes += f" ({e['gap']})"
    return notes


def table(rows: list[list[str]], head: list[str]) -> list[str]:
    out = ["| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
    out += ["| " + " | ".join(r) + " |" for r in rows]
    return out


def by_area(ledger: dict, statuses: tuple[str, ...], level: int) -> list[str]:
    out = []
    for area in ledger["area"]:
        entries = [e for e in ledger["capability"]
                   if e["area"] == area["id"] and e["status"] in statuses]
        if not entries:
            continue
        out += [f"{'#' * level} {area['title']}", ""]
        out += table([[e["feature"], status_cell(e["status"]), notes_cell(e)] for e in entries],
                     ["Feature", "Status", "Notes"])
        out.append("")
    return out[:-1]


def highlights(ledger: dict, kind: str) -> list[str]:
    """The texts of the short list `kind` (`works` or `not_yet`), in the
    order of the ledger's [highlights] table."""
    by_id = {e["id"]: e for e in ledger["capability"]}
    return [by_id[i][kind] for i in ledger["highlights"][kind]]


def render(view: str, args: str, ledger: dict, target: Path) -> str:
    m = re.search(r"level=(\d)", args)
    level = int(m.group(1)) if m else 2
    if view == "statuses":
        lines = [f"- {icon} **{label}**: {meaning}." for icon, label, meaning in STATUSES.values()]
    elif view == "matrix":
        lines = by_area(ledger, tuple(STATUSES), level)
    elif view == "supported":
        lines = by_area(ledger, SUPPORTED_VIEW, level)
    elif view == "limitations":
        lines = by_area(ledger, LIMITATIONS_VIEW, level)
    elif view == "highlights":
        lines = ["**Works today:**", ""] + [f"- {h}" for h in highlights(ledger, "works")]
        lines += ["", "**Not yet:**", ""] + [f"- {h}" for h in highlights(ledger, "not_yet")]
    elif view == "annotations":
        lines = table([[f"`@custom:strata {a['syntax']}`", a["placement"], one_line(a["meaning"])]
                       for a in ledger["annotation"]], ["Annotation", "Placement", "Meaning"])
    elif view == "flags":
        lines = table([[f"`{f['name']}`", one_line(f["effect"])] for f in ledger["flag"]],
                      ["Option", "Effect"])
    elif view == "gaps":
        lines = table([[g["id"], one_line(g["baseline"]), g["status"].capitalize(), one_line(g["now"])]
                       for g in ledger["gap"]], ["Gap", "Baseline", "Status", "Now"])
        rest = [e for e in ledger["capability"] if "gap" not in e and e["status"] != "verified"]
        lines += ["", "Limitations without a baseline gap, by capability id:", ""]
        lines += table([[f"`{e['id']}`", e["feature"], status_cell(e["status"])] for e in rest],
                       ["Capability", "Feature", "Status"])
    else:
        raise LedgerError(f"unknown view {view!r}")
    return link("\n".join([NOTICE] + lines), target) + "\n"


def regenerate(text: str, ledger: dict, target: Path) -> str:
    out, pos = [], 0
    for m in BEGIN.finditer(text):
        if m.start() < pos:
            continue
        end = f"<!-- capabilities:end {m.group('view')} -->"
        stop = text.find(end, m.end())
        if stop < 0:
            raise LedgerError(f"{target.relative_to(REPO)}: no `{end}`")
        out += [text[pos:m.end()], render(m.group("view"), m.group("args"), ledger, target)]
        pos = stop
    return "".join(out) + text[pos:]


# Used by docs/site/_src/build.py for the landing page.

def inline_html(md: str) -> str:
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", html.escape(md, quote=False))


def html_highlights(ledger: dict, kind: str) -> str:
    return "\n".join(f"            <li>{inline_html(h)}</li>" for h in highlights(ledger, kind))


def html_annotations(ledger: dict) -> str:
    return "\n".join(
        f"          <tr><td><code>{html.escape(a['syntax'])}</code></td><td>{html.escape(a['placement'])}</td>"
        f"<td>{inline_html(one_line(a['meaning']))}</td></tr>" for a in ledger["annotation"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true",
                        help="fail if a generated section is out of date instead of rewriting it")
    opts = parser.parse_args()
    ledger = load()
    problems = check(ledger)
    for rel in TARGETS:
        path = REPO / rel
        text = path.read_text()
        try:
            new = regenerate(text, ledger, path)
        except LedgerError as err:
            problems.append(str(err))
            continue
        if new != text:
            if opts.check:
                problems.append(f"{rel}: generated sections are out of date "
                                "(run python3 scripts/capabilities.py)")
            else:
                path.write_text(new)
                print(f"updated {rel}")
    for p in problems:
        print(f"❌ {p}", file=sys.stderr)
    n = len(ledger["capability"])
    if problems:
        print(f"{len(problems)} problem(s) in the capability ledger ({n} entries)", file=sys.stderr)
        return 1
    print(f"capability ledger: {n} entries, every witness holds")
    return 0


if __name__ == "__main__":
    sys.exit(main())
