#!/usr/bin/env bash
# Checks that every module in lib/ has a moduledoc.
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
