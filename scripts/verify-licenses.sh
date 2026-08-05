#!/bin/bash
# Verifies that the license and attribution files required by
# ROADMAP.md task M0-02 are present and contain the expected content.
# Exits non-zero on the first failure so it can be used as a CI gate.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0

check_file_exists() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "✗ Missing required file: ${path}"
    fail=1
  else
    echo "✓ Found ${path}"
  fi
}

check_contains() {
  local path="$1"
  local needle="$2"
  local label="$3"
  if [ ! -f "$path" ]; then
    return
  fi
  if ! grep -qF "$needle" "$path"; then
    echo "✗ ${path} is missing expected content: ${label}"
    fail=1
  else
    echo "✓ ${path} contains: ${label}"
  fi
}

check_file_exists "LICENSE"
check_contains "LICENSE" "MIT License" "MIT License header"
check_contains "LICENSE" "Copyright (c) 2026 arietan" "preserved upstream LiteEdit copyright"

check_file_exists "NOTICE.md"
check_contains "NOTICE.md" "LiteEdit" "LiteEdit attribution"
check_contains "NOTICE.md" "https://github.com/arietan/lite-edit" "upstream repository URL"

check_file_exists "UPSTREAM.md"
check_contains "UPSTREAM.md" "Base commit SHA" "recorded base commit SHA"

check_file_exists "README.md"
check_contains "README.md" "not affiliated with or endorsed by the developers of Maru Editor" \
  "independent-project / non-affiliation statement"

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "License verification FAILED."
  exit 1
fi

echo ""
echo "License verification passed."
