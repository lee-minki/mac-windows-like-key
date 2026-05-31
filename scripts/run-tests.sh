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

# 공통 source set (smoke 들이 컴파일 시 필요)
COMMON_SOURCES=(
  WinMacKey/Models/MappingProfile.swift
  WinMacKey/Models/KeyEvent.swift
  WinMacKey/Services/HIDRemapper.swift
  WinMacKey/Services/LogService.swift
  WinMacKey/Services/KeyInterceptor.swift
  WinMacKey/Services/ContextManager.swift
  WinMacKey/Services/KeyboardDeviceManager.swift
)
COMMON_FRAMEWORKS=(-framework AppKit -framework Carbon -framework IOKit)

# ── HID lifecycle invariant smoke ─────────────────────────────────────────────
# KeyInterceptor.init() 이 HID 시스템 상태를 건드리지 않는지 검증
swiftc \
  "${COMMON_SOURCES[@]}" \
  tests/hid_lifecycle_smoke.swift \
  -o build/tests/hid_lifecycle_smoke \
  "${COMMON_FRAMEWORKS[@]}"

build/tests/hid_lifecycle_smoke

# ── Engine-OFF UI invariant smoke ─────────────────────────────────────────────
# 엔진 OFF 상태에서 UI 가 KeyInterceptor 외부 메서드 호출해도 HID 안 건드림
swiftc \
  "${COMMON_SOURCES[@]}" \
  tests/engine_off_ui_smoke.swift \
  -o build/tests/engine_off_ui_smoke \
  "${COMMON_FRAMEWORKS[@]}"

build/tests/engine_off_ui_smoke

# ── HID Ownership semantics smoke ─────────────────────────────────────────────
# takeOwnership / releaseOwnership / internalClearAllForTermination 의 invariant 4종
swiftc \
  "${COMMON_SOURCES[@]}" \
  tests/ownership_smoke.swift \
  -o build/tests/ownership_smoke \
  "${COMMON_FRAMEWORKS[@]}"

build/tests/ownership_smoke

# ── Toggle-OFF snapshot restore smoke ─────────────────────────────────────────
# HIGH 1 fix 의 restorePreExistingMappingsAndClearInternal 동작 검증
swiftc \
  "${COMMON_SOURCES[@]}" \
  tests/toggle_off_snapshot_smoke.swift \
  -o build/tests/toggle_off_snapshot_smoke \
  "${COMMON_FRAMEWORKS[@]}"

build/tests/toggle_off_snapshot_smoke

# ── Remote Mac Mode flag smoke ────────────────────────────────────────────────
# v1.3.4 NEW: isRemoteMacAppFocused 외부 설정, vdi/remote flag 독립성 검증
swiftc \
  "${COMMON_SOURCES[@]}" \
  tests/remote_mac_mode_smoke.swift \
  -o build/tests/remote_mac_mode_smoke \
  "${COMMON_FRAMEWORKS[@]}"

build/tests/remote_mac_mode_smoke

# ── Trigger branching invariant smoke ─────────────────────────────────────────
# KeyInterceptor 의 mode flag 들이 외부 설정 가능 + 서로 독립 + triggerKeyCode=F16 invariant
# v1.3.4 와 v1.3.5 둘 다 통과해야 하는 회귀 lock-down
swiftc \
  "${COMMON_SOURCES[@]}" \
  tests/trigger_branching_smoke.swift \
  -o build/tests/trigger_branching_smoke \
  "${COMMON_FRAMEWORKS[@]}"

build/tests/trigger_branching_smoke

# ── KeyboardDeviceManager capture mode smoke (v1.3.6 NEW) ─────────────────────
# Press-to-bind UX 의 핵심 — startCapture / cancelCapture / supersede invariant
swiftc \
  "${COMMON_SOURCES[@]}" \
  tests/keyboard_capture_smoke.swift \
  -o build/tests/keyboard_capture_smoke \
  "${COMMON_FRAMEWORKS[@]}"

build/tests/keyboard_capture_smoke

# ── Commit window invariant smoke (v1.7.0 NEW) ────────────────────────────────
# bufferedReplayWindow 의 guard (VDI/Terminal/init) + begin·complete·fail·supersede 안전성
swiftc \
  "${COMMON_SOURCES[@]}" \
  tests/commit_window_smoke.swift \
  -o build/tests/commit_window_smoke \
  "${COMMON_FRAMEWORKS[@]}"

build/tests/commit_window_smoke

# ── Buffered replay adaptive timeout smoke (v1.7.0 NEW) ───────────────────────
# P13 후속 — IME-sensitive 화이트리스트 (Word/Pages 등) 의 adaptive timeout 동작
swiftc \
  "${COMMON_SOURCES[@]}" \
  tests/buffered_replay_smoke.swift \
  -o build/tests/buffered_replay_smoke \
  "${COMMON_FRAMEWORKS[@]}"

build/tests/buffered_replay_smoke

# ── Script-level guardrails ───────────────────────────────────────────────────
bash scripts/check-version-consistency.sh
bash scripts/check-release-workflow.sh
bash scripts/check-reset-keys.sh
