#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

python3 - <<'PY'
import re
from pathlib import Path

reset = Path('WinMacKey/Services/ResetService.swift').read_text()
doctor = Path('WinMacKey/Services/DoctorService.swift').read_text()

shared_match = re.search(
    r'enum\s+AppManagedDefaultsKeys\s*\{.*?static\s+let\s+all:\s*\[String\]\s*=\s*\[(.*?)\]',
    reset,
    re.S,
)
reset_uses_shared = 'private let userDefaultsKeys = AppManagedDefaultsKeys.all' in reset
doctor_uses_shared = 'for key in AppManagedDefaultsKeys.all' in doctor
if not shared_match:
    raise SystemExit('reset key check failed: AppManagedDefaultsKeys.all not found')

extract = lambda body: set(re.findall(r'"([A-Za-z0-9_.]+)"', body))
shared_keys = extract(shared_match.group(1))
required = {
    'WinMacKey.Profiles',
    'LastUpdateCheck',
    'AutoCheckUpdates',
    'CustomVirtualizationApps',
    'CustomTerminalApps',
    'CustomRemoteMacApps',
    'activeMappingProfileId',
    'visualCustomMappings',
    'eventViewerAlwaysOnTop',
    'savedKeyboardProfiles',
    'languagePairSource1',
    'languagePairSource2',
    'startEngineOnAppLaunch',
    'hasCompletedFirstRunOnboarding',
    'WinMacKey.AccessibilityWasEverGranted',
}

problems = []
if not reset_uses_shared:
    problems.append('ResetService does not use AppManagedDefaultsKeys.all')
if not doctor_uses_shared:
    problems.append('DoctorService does not use AppManagedDefaultsKeys.all')
missing_shared = required - shared_keys
if missing_shared:
    problems.append('AppManagedDefaultsKeys missing: ' + ', '.join(sorted(missing_shared)))

if problems:
    for problem in problems:
        print('reset key check failed:', problem)
    print('AppManagedDefaultsKeys:', ', '.join(sorted(shared_keys)))
    raise SystemExit(1)

print('reset key parity: PASS')
PY
