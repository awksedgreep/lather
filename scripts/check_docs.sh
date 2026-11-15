#!/usr/bin/env bash
# Checks that every module in lib/ has a moduledoc, and that ExDoc builds the
# documentation without warnings (for example, docs referencing a hidden
# function such as a Plug callback with no @doc).
# Modules without @moduledoc are listed and the script exits non-zero.

set -euo pipefail

missing=0

while IFS= read -r file; do
  if ! grep -q '@moduledoc' "$file"; then
    echo "missing moduledoc: $file"
    missing=1
  fi
done < <(find lib -name '*.ex' | sort)

if [ "$missing" -eq 0 ]; then
  echo "All modules have moduledocs."
else
  exit 1
fi

doc_output="$(mix docs 2>&1)"

if echo "$doc_output" | grep -q "warning:"; then
  echo "ExDoc reported warnings:"
  echo "$doc_output" | grep "warning:"
  exit 1
fi

echo "Docs build with no warnings."
