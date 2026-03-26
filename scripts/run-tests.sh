#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

mkdir -p build/tests

swiftc \
  WinMacKey/Models/MappingProfile.swift \
  tests/mapping_profile_smoke.swift \
  -o build/tests/mapping_profile_smoke

build/tests/mapping_profile_smoke
