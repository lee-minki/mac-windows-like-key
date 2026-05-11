#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

python3 - <<'PY'
import re
from pathlib import Path

reset = Path('WinMacKey/Services/ResetService.swift').read_text()
doctor = Path('WinMacKey/Services/DoctorService.swift').read_text()

reset_match = re.search(r'private let userDefaultsKeys = \[(.*?)\]', reset, re.S)
doctor_match = re.search(r'let keys = \[(.*?)\]', doctor, re.S)
if not reset_match:
    raise SystemExit('reset key check failed: ResetService userDefaultsKeys not found')
if not doctor_match:
    raise SystemExit('reset key check failed: DoctorService emergencyRecovery keys not found')

extract = lambda body: set(re.findall(r'"([A-Za-z0-9_.]+)"', body))
reset_keys = extract(reset_match.group(1))
doctor_keys = extract(doctor_match.group(1))
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

problems = []
if reset_keys != doctor_keys:
    problems.append('ResetService and DoctorService key sets differ')
missing_reset = required - reset_keys
missing_doctor = required - doctor_keys
if missing_reset:
    problems.append('ResetService missing: ' + ', '.join(sorted(missing_reset)))
if missing_doctor:
    problems.append('DoctorService missing: ' + ', '.join(sorted(missing_doctor)))

if problems:
    for problem in problems:
        print('reset key check failed:', problem)
    print('ResetService:', ', '.join(sorted(reset_keys)))
    print('DoctorService:', ', '.join(sorted(doctor_keys)))
    raise SystemExit(1)

print('reset key parity: PASS')
PY
