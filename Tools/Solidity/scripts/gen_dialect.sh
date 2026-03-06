#!/bin/sh
# Generate the Solidity DDM dialect and verify it with Strata.
set -e

script_dir="$(cd "$(dirname "$0")" && pwd)"
tools_solidity_dir="$(cd "$script_dir/.." && pwd)"
cd "$tools_solidity_dir"

strata=../../.lake/build/bin/strata

if [ ! -f "$strata" ]; then
  echo "strata is not built: $strata"
  exit 1
fi

dialect_dir="dialects"
mkdir -p "$dialect_dir"

python3 -m src.solast dialect "$dialect_dir"
$strata check "$dialect_dir/Solidity.dialect.st.ion"
echo "Dialect check passed."
