#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

mkdir -p build/tests

# ── Mapping profile smoke ─────────────────────────────────────────────────────
swiftc \
  WinMacKey/Models/MappingProfile.swift \
  tests/mapping_profile_smoke.swift \
  -o build/tests/mapping_profile_smoke

build/tests/mapping_profile_smoke

# ── HID lifecycle invariant smoke ─────────────────────────────────────────────
# KeyInterceptor.init() 이 HID 시스템 상태를 건드리지 않는지 검증
swiftc \
  WinMacKey/Models/MappingProfile.swift \
  WinMacKey/Models/KeyEvent.swift \
  WinMacKey/Services/HIDRemapper.swift \
  WinMacKey/Services/LogService.swift \
  WinMacKey/Services/KeyInterceptor.swift \
  tests/hid_lifecycle_smoke.swift \
  -o build/tests/hid_lifecycle_smoke \
  -framework AppKit \
  -framework Carbon

build/tests/hid_lifecycle_smoke

# ── Script-level guardrails ───────────────────────────────────────────────────
bash scripts/check-version-consistency.sh
bash scripts/check-release-workflow.sh
bash scripts/check-reset-keys.sh
