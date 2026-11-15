#!/usr/bin/env bash
# Runs the test suite with coverage and fails if total coverage drops below
# COVERAGE_MIN (default 80).
#
#   COVERAGE_MIN=85 ./scripts/coverage_gate.sh

set -euo pipefail

min="${COVERAGE_MIN:-80}"

output=$(mix test --cover)

total=$(echo "$output" | grep -E '^\|\s+[0-9]+\.[0-9]+%\s*\|\s*Total\s*\|' | head -1)

if [ -z "$total" ]; then
  echo "could not parse coverage total from mix test --cover output"
  exit 1
fi

percent=$(echo "$total" | tr -d '| ' | sed 's/%Total//')

echo "Total coverage: ${percent}% (minimum ${min}%)"

awk "BEGIN { exit !(${percent} >= ${min}) }"
