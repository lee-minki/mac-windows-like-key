#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

python3 - <<'PY'
import re
from pathlib import Path

reset = Path('WinMacKey/Services/ResetService.swift').read_text()
doctor = Path('WinMacKey/Services/DoctorService.swift').read_text()

shared_match = re.search(r'static let all: \[String\] = \[(.*?)\]', reset, re.S)
if not shared_match:
    raise SystemExit('reset key check failed: AppManagedDefaultsKeys.all not found')
if 'userDefaultsKeys = AppManagedDefaultsKeys.all' not in reset:
    raise SystemExit('reset key check failed: ResetService does not use shared keys')
if 'for key in AppManagedDefaultsKeys.all' not in doctor:
    raise SystemExit('reset key check failed: DoctorService does not use shared keys')

extract = lambda body: set(re.findall(r'"([A-Za-z0-9_.]+)"', body))
shared_keys = extract(shared_match.group(1))
required = {
    'WinMacKey.Profiles',
    'LastUpdateCheck',
    'AutoCheckUpdates',
    'CustomVirtualizationApps',
    'CustomTerminalApps',
    'activeMappingProfileId',
    'visualCustomMappings',
    'eventViewerAlwaysOnTop',
    'savedKeyboardProfiles',
    'languagePairSource1',
    'languagePairSource2',
    'startEngineOnAppLaunch',
}

missing = required - shared_keys
if missing:
    print('reset key check failed: shared keys missing: ' + ', '.join(sorted(missing)))
    print('Shared keys:', ', '.join(sorted(shared_keys)))
    raise SystemExit(1)

print('reset key parity: PASS')
PY
