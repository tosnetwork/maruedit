#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0

dependencies_json="$(swift package dump-package | /usr/bin/plutil -extract dependencies json -o - - 2>/dev/null)"
if [ "$dependencies_json" != "[]" ]; then
  echo "error: Package.swift declares package dependencies" >&2
  fail=1
else
  echo "ok: no third-party Swift package dependencies"
fi

risky_files="$(git ls-files | grep -Ei '\.(p12|pfx|cer|der|mobileprovision|pem|key|keystore)$' || true)"
if [ -n "$risky_files" ]; then
  echo "error: tracked certificate/key material:" >&2
  echo "$risky_files" >&2
  fail=1
else
  echo "ok: no tracked certificate or private-key file types"
fi

secret_hits="$(git grep -nEI \
  -e 'AKIA[0-9A-Z]{16}' \
  -e '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' \
  -e '(api[_-]?key|client[_-]?secret|notary[_-]?password)[[:space:]]*[:=]' \
  -- ':!scripts/security-audit.sh' ':!docs/*' ':!SECURITY.md' || true)"
if [ -n "$secret_hits" ]; then
  echo "error: possible tracked secret:" >&2
  echo "$secret_hits" >&2
  fail=1
else
  echo "ok: tracked-source secret patterns absent"
fi

test "$fail" -eq 0
