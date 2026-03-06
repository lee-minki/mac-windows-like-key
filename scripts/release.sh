#!/bin/bash
# WinMac Key Release Script
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.2.0
#
# Prerequisites:
#   - gh CLI (brew install gh) + gh auth login 완료

set -e

VERSION=${1:?"Usage: ./scripts/release.sh <version>"}
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="/tmp/WinMacKey-release"
SCHEME="WinMacKey"
PRODUCT_NAME="WinMacKey"

echo "🚀 WinMac Key v${VERSION} 릴리스 시작"
echo ""

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── WinMacKey 앱 빌드 ─────────────────────────────────────────────────────────
echo "🔨 WinMacKey 빌드 중 (Release)..."
xcodebuild \
    -project "${PROJECT_DIR}/WinMacKey.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    clean build \
    CONFIGURATION_BUILD_DIR="${BUILD_DIR}/Build" \
    2>&1 | tail -5

if [ ! -d "${BUILD_DIR}/Build/${PRODUCT_NAME}.app" ]; then
    echo "❌ 빌드 실패: ${PRODUCT_NAME}.app 없음"
    exit 1
fi
echo "✅ 앱 빌드 완료"
echo ""

# ── ZIP 생성 ──────────────────────────────────────────────────────────────────
ZIP_NAME="${PRODUCT_NAME}-v${VERSION}.zip"
echo "🗜️  ZIP 생성 중..."
cd "${BUILD_DIR}/Build"
zip -r "${BUILD_DIR}/${ZIP_NAME}" "${PRODUCT_NAME}.app" --quiet
echo "   ✅ ${ZIP_NAME} ($(du -h "${BUILD_DIR}/${ZIP_NAME}" | cut -f1))"
echo ""

# ── GitHub Release ────────────────────────────────────────────────────────────
echo "📦 GitHub Release v${VERSION} 생성 중..."
cd "$PROJECT_DIR"

gh release create "v${VERSION}" \
    "${BUILD_DIR}/${ZIP_NAME}" \
    --title "WinMac Key v${VERSION}" \
    --notes "## WinMac Key v${VERSION}

### 변경 사항
- (릴리스 노트를 여기에 작성하세요)

### 설치 방법
1. \`${ZIP_NAME}\` 다운로드
2. 압축 해제 → \`${PRODUCT_NAME}.app\`
3. \`/Applications/\` 폴더로 이동
4. 우클릭 → 열기 (최초 1회)

또는 앱 내 **업데이트 확인** 기능으로 자동 설치됩니다."

echo ""
echo "🎉 릴리스 v${VERSION} 완료!"
echo "   https://github.com/lee-minki/mac-windows-like-key/releases/tag/v${VERSION}"
