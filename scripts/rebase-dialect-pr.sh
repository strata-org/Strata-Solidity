#!/usr/bin/env bash
# rebase-dialect-pr.sh — rebase a Phase-2 dialect PR onto the current base,
# automatically resolving the binary Ion conflict by regenerating from the
# merged base_dialect.py, and validating the result with a build + golden suite.
#
# Usage:
#   ./scripts/rebase-dialect-pr.sh <branch-name> [--push]
#
# Example:
#   ./scripts/rebase-dialect-pr.sh feat/phase2-control-flow --push
#
# What it does (same as the manual process for #19):
#   1. Fetches origin and checks out the PR branch.
#   2. Rebases onto origin/feat/upstream-port.
#   3. If the only conflict is the binary Ion:
#      a. Regenerates it from the (cleanly-merged) base_dialect.py.
#      b. Marks resolved and continues the rebase.
#   4. Busts stale dialect-derived oleans.
#   5. Rebuilds (lake build).
#   6. Runs the golden suite (test/run_tests.sh).
#   7. If --push: force-pushes with lease.
#
# Prerequisites: solc, python3, lake, Strata submodule initialized.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

BRANCH="${1:-}"
PUSH="${2:-}"
BASE="origin/feat/upstream-port"

if [ -z "$BRANCH" ]; then
  echo "Usage: $0 <branch-name> [--push]" >&2
  exit 1
fi

echo "▶ Fetching origin..."
git fetch origin --quiet

echo "▶ Checking out $BRANCH..."
git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH"
git reset --hard "origin/$BRANCH"

echo "▶ Rebasing onto $BASE..."
if git rebase "$BASE" 2>/dev/null; then
  echo "  ✓ Rebase clean (no conflicts)."
else
  echo "  ⚠ Rebase paused — checking conflicts..."

  # Loop: resolve Ion conflicts commit-by-commit until rebase completes
  while true; do
    CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
    if [ -z "$CONFLICTS" ]; then
      echo "  ✓ No more conflicts."
      break
    fi

    # Check that the ONLY conflict is the binary Ion
    NON_ION=$(echo "$CONFLICTS" | grep -v "Solidity.dialect.st.ion" || true)
    if [ -n "$NON_ION" ]; then
      echo "  ✗ Non-Ion conflicts found — manual resolution needed:" >&2
      echo "$NON_ION" >&2
      echo "  Run: git rebase --abort  to undo" >&2
      exit 1
    fi

    echo "  → Regenerating Ion from merged base_dialect.py..."
    STRATA_PYTHON="$(cd Strata/Tools/Python 2>/dev/null && pwd)"
    (cd Tools/Solidity && PYTHONPATH="${STRATA_PYTHON}:${PYTHONPATH:-}" \
      python3 -m src.solast dialect dialects)

    git add Tools/Solidity/dialects/Solidity.dialect.st.ion
    echo "  → Conflict resolved, continuing rebase..."

    if GIT_EDITOR=true git rebase --continue 2>/dev/null; then
      echo "  ✓ Rebase complete."
      break
    fi
    # If rebase paused again (another commit with Ion conflict), loop back
  done
fi

echo "▶ Busting stale dialect-derived oleans..."
setopt null_glob 2>/dev/null || shopt -s nullglob 2>/dev/null || true
for base in lib/lean ir; do
  d=".lake/build/${base}/StrataSolidity"
  for f in "$d"/SolidityDialect.*; do rm -f "$f"; done
  rm -f "$d"/Solidity.* "$d"/ReadSolidity.* 2>/dev/null || true
  rm -rf "$d"/SolTranslator 2>/dev/null || true
done

echo "▶ Building (lake build)..."
if ! lake build > /tmp/rebase-dialect-build.log 2>&1; then
  echo "  ✗ Build failed. See /tmp/rebase-dialect-build.log" >&2
  tail -15 /tmp/rebase-dialect-build.log >&2
  exit 1
fi
echo "  ✓ Build OK ($(grep -c '✔' /tmp/rebase-dialect-build.log) jobs)"

echo "▶ Running golden suite..."
RESULT=$(bash test/run_tests.sh 2>&1 | grep -E "passed, .* failed" | head -1)
echo "  $RESULT"
if echo "$RESULT" | grep -q "0 failed"; then
  echo "  ✓ Golden suite passed."
else
  echo "  ✗ Golden suite has failures!" >&2
  exit 1
fi

if [ "$PUSH" = "--push" ]; then
  echo "▶ Force-pushing $BRANCH..."
  git push --force-with-lease origin "$BRANCH"
  echo "  ✓ Pushed."
else
  echo ""
  echo "Done. To push:  git push --force-with-lease origin $BRANCH"
fi

echo ""
echo "═══════════════════════════════════════════"
echo "  $BRANCH rebased + Ion regenerated ✓"
echo "═══════════════════════════════════════════"
