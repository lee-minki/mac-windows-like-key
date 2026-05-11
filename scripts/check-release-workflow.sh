#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

python3 - <<'PY'
from pathlib import Path
text = Path('.github/workflows/release.yml').read_text()
if 'KEYCHAIN_PASSWORD=***' in text:
    raise SystemExit('release workflow check failed: placeholder/corrupt KEYCHAIN_PASSWORD assignment remains')
if 'KEYCHAIN_PASSWORD=$(openssl rand -hex 16)' not in text:
    raise SystemExit('release workflow check failed: expected openssl-generated KEYCHAIN_PASSWORD assignment missing')
PY

bash -n <(python3 - <<'PY'
from pathlib import Path
text = Path('.github/workflows/release.yml').read_text().splitlines()
in_run = False
indent = None
buf = []
for line in text:
    stripped = line.lstrip(' ')
    leading = len(line) - len(stripped)
    if stripped == 'run: |':
        in_run = True
        indent = None
        continue
    if in_run:
        if stripped and not stripped.startswith('#') and indent is None:
            indent = leading
        if indent is not None and leading < indent and stripped:
            in_run = False
            indent = None
            continue
        if indent is not None:
            buf.append(line[indent:])
print('\n'.join(buf))
PY
)

echo "release workflow syntax: PASS"
