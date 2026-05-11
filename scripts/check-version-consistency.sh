#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

info_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' WinMacKey/Info.plist)
info_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' WinMacKey/Info.plist)

project_versions=$(grep -E 'MARKETING_VERSION = ' WinMacKey.xcodeproj/project.pbxproj | sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/' | sort -u)
project_builds=$(grep -E 'CURRENT_PROJECT_VERSION = ' WinMacKey.xcodeproj/project.pbxproj | sed -E 's/.*CURRENT_PROJECT_VERSION = ([^;]+);/\1/' | sort -u)

if [ "$(printf '%s\n' "$project_versions" | sed '/^$/d' | wc -l | tr -d ' ')" -ne 1 ]; then
  echo "version check failed: project has multiple MARKETING_VERSION values:" >&2
  printf '%s\n' "$project_versions" >&2
  exit 1
fi

if [ "$(printf '%s\n' "$project_builds" | sed '/^$/d' | wc -l | tr -d ' ')" -ne 1 ]; then
  echo "version check failed: project has multiple CURRENT_PROJECT_VERSION values:" >&2
  printf '%s\n' "$project_builds" >&2
  exit 1
fi

project_version=$(printf '%s\n' "$project_versions" | sed '/^$/d')
project_build=$(printf '%s\n' "$project_builds" | sed '/^$/d')

if [ "$info_version" != "$project_version" ]; then
  echo "version check failed: Info.plist version '$info_version' != project MARKETING_VERSION '$project_version'" >&2
  exit 1
fi

if [ "$info_build" != "$project_build" ]; then
  echo "version check failed: Info.plist build '$info_build' != project CURRENT_PROJECT_VERSION '$project_build'" >&2
  exit 1
fi

if ! grep -qE "\[Unreleased\] — v${info_version}|\[${info_version}\] — [0-9]{4}-[0-9]{2}-[0-9]{2}" CHANGELOG.md; then
  echo "version check failed: CHANGELOG.md missing entry for v${info_version} (expect [Unreleased] — v${info_version} or [${info_version}] — YYYY-MM-DD)" >&2
  exit 1
fi

if grep -RInE 'WinMac Key v2\.0|v1\.3 사용 매뉴얼|macOS 13\.0' README.md docs CHANGELOG.md >/tmp/winmackey-version-stale.txt; then
  echo "version check failed: stale user-facing version/support text found:" >&2
  cat /tmp/winmackey-version-stale.txt >&2
  exit 1
fi

echo "version consistency: PASS (${info_version} build ${info_build})"
