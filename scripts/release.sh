#!/bin/bash
# WinMac Key Release Script
# Usage: ./scripts/release.sh <version> [--no-release]
# Example: ./scripts/release.sh 1.3.0
#
# 산출물:
#   - WinMacKey-v<version>.zip  앱 내 자동 업데이트 채널용
#   - WinMacKey-v<version>.dmg  팀/외부 배포용
#
# Signing:
#   기본적으로 "WinMacKey Self-Signed" identity로 서명합니다 (Apple Developer ID는 아니지만
#   동일 identity로 서명된 빌드 간 손쉬운 사용 권한이 영속됩니다).
#   identity가 없으면 ad-hoc 서명으로 fallback (매 빌드마다 권한 재요청).
#   영구 셋업: ./scripts/setup-signing.sh
#   override:  SIGN_IDENTITY="<name>" ./scripts/release.sh ...
#
# Prerequisites:
#   - gh CLI (brew install gh) + gh auth login 완료 (GitHub Release 업로드 시)
#   - --no-release 플래그를 주면 로컬 산출물만 만들고 종료

set -e

VERSION=${1:?"Usage: ./scripts/release.sh <version> [--no-release]"}
SKIP_RELEASE=0
if [ "${2:-}" = "--no-release" ]; then
    SKIP_RELEASE=1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="/tmp/WinMacKey-release"
SCHEME="WinMacKey"
PRODUCT_NAME="WinMacKey"

: "${SIGN_IDENTITY:=WinMacKey Self-Signed}"
: "${UPDATE_SIGN_KEY:=$HOME/.config/winmackey/update-signing.key}"

# Signing identity 검증 — self-signed cert는 find-identity -p codesigning 에 안 잡히므로
# 실제 codesign 동작 테스트로 판정 (가장 신뢰 가능)
verify_sign_identity() {
    local test_file="$(mktemp)"
    cp /bin/ls "$test_file"
    if codesign --force -s "$SIGN_IDENTITY" "$test_file" 2>/dev/null \
       && codesign -dvvv "$test_file" 2>&1 | grep -q "Authority=$SIGN_IDENTITY"; then
        rm -f "$test_file"
        return 0
    fi
    rm -f "$test_file"
    return 1
}

SIGN_FLAGS=()
if verify_sign_identity; then
    SIGN_FLAGS=(
        CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
        CODE_SIGN_STYLE=Manual
        OTHER_CODE_SIGN_FLAGS="--timestamp=none"
    )
    SIGN_MODE="stable (identity: $SIGN_IDENTITY)"
else
    SIGN_FLAGS=(
        CODE_SIGN_IDENTITY="-"
        CODE_SIGN_STYLE=Manual
    )
    SIGN_MODE="ad-hoc (권한 매 빌드마다 재요청됨 — 영구 셋업: ./scripts/setup-signing.sh)"
fi

echo "🚀 WinMac Key v${VERSION} 릴리스 시작"
echo "   🔐 서명: $SIGN_MODE"
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
    "${SIGN_FLAGS[@]}" \
    2>&1 | tail -5

APP_PATH="${BUILD_DIR}/Build/${PRODUCT_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 빌드 실패: ${PRODUCT_NAME}.app 없음"
    exit 1
fi
echo "✅ 앱 빌드 완료"
echo ""

# ── ZIP 생성 (자동 업데이트 채널용) ─────────────────────────────────────────────
ZIP_NAME="${PRODUCT_NAME}-v${VERSION}.zip"
ZIP_PATH="${BUILD_DIR}/${ZIP_NAME}"
echo "🗜️  ZIP 생성 중..."
cd "${BUILD_DIR}/Build"
zip -r "${ZIP_PATH}" "${PRODUCT_NAME}.app" --quiet
echo "   ✅ ${ZIP_NAME} ($(du -h "${ZIP_PATH}" | cut -f1))"
cd "$PROJECT_DIR"
echo ""

# ── DMG 생성 (팀/외부 배포용) ────────────────────────────────────────────────
DMG_NAME="${PRODUCT_NAME}-v${VERSION}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
STAGING="${BUILD_DIR}/dmg-staging"

echo "💿 DMG 생성 중..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# 빌드 산출물에 남아 있는 quarantine 흔적 제거 (있다면)
xattr -cr "$STAGING/${PRODUCT_NAME}.app" 2>/dev/null || true

hdiutil create \
    -volname "WinMacKey" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

echo "   ✅ ${DMG_NAME} ($(du -h "${DMG_PATH}" | cut -f1))"
echo ""

# ── Ed25519 서명 (자동 업데이트 무결성 검증용) ────────────────────────────────
# LibreSSL은 Ed25519 미지원 — OpenSSL 3.x (brew) 사용
ED_OPENSSL=""
for candidate in \
    "/opt/homebrew/opt/openssl@3/bin/openssl" \
    "/opt/homebrew/bin/openssl" \
    "/usr/local/opt/openssl@3/bin/openssl" \
    "/usr/local/bin/openssl"
do
    if [ -x "$candidate" ] && "$candidate" version 2>/dev/null | grep -qE "^OpenSSL 3\."; then
        ED_OPENSSL="$candidate"
        break
    fi
done

SIG_FILES=()
if [ -f "$UPDATE_SIGN_KEY" ]; then
    if [ -z "$ED_OPENSSL" ]; then
        echo "❌ Update signing key는 있지만 OpenSSL 3.x를 찾지 못함 (LibreSSL은 Ed25519 미지원)"
        echo "   brew install openssl@3"
        exit 1
    fi
    echo "✍️  Ed25519 서명 생성 중 ($($ED_OPENSSL version))..."
    for asset in "$ZIP_PATH" "$DMG_PATH"; do
        sig_path="${asset}.sig"
        if "$ED_OPENSSL" pkeyutl -sign -inkey "$UPDATE_SIGN_KEY" -rawin -in "$asset" -out "$sig_path" 2>/dev/null; then
            echo "   ✅ $(basename "$sig_path") ($(du -h "$sig_path" | cut -f1))"
            SIG_FILES+=("$sig_path")
        else
            echo "   ❌ 서명 실패: $(basename "$asset")"
            exit 1
        fi
    done
    echo ""
else
    echo "⚠️  Update signing key 없음: $UPDATE_SIGN_KEY"
    echo "    .sig 파일을 동봉하지 않으므로 앱의 자동 업데이트 검증이 활성화된 경우 실패합니다."
    echo "    영구 셋업: ./scripts/setup-update-signing.sh"
    echo ""
fi

if [ "$SKIP_RELEASE" -eq 1 ]; then
    echo "ℹ️  --no-release 플래그: GitHub Release 업로드를 건너뜁니다."
    echo ""
    echo "   📦 산출물:"
    echo "      $ZIP_PATH"
    echo "      $DMG_PATH"
    for sig in "${SIG_FILES[@]:-}"; do
        [ -n "$sig" ] && echo "      $sig"
    done
    exit 0
fi

# ── GitHub Release ────────────────────────────────────────────────────────────
echo "📦 GitHub Release v${VERSION} 생성 중..."

RELEASE_ASSETS=("${ZIP_PATH}" "${DMG_PATH}")
for sig in "${SIG_FILES[@]:-}"; do
    [ -n "$sig" ] && RELEASE_ASSETS+=("$sig")
done

gh release create "v${VERSION}" \
    "${RELEASE_ASSETS[@]}" \
    --title "WinMac Key v${VERSION}" \
    --notes "## WinMac Key v${VERSION}

### 변경 사항
- (릴리스 노트를 여기에 작성하세요)

### 다운로드
- \`${DMG_NAME}\` : 일반 사용자 (드래그 & 드롭 설치)
- \`${ZIP_NAME}\` : 앱 내 자동 업데이트용

### ⚠️ 최초 실행 안내 (Apple 미서명 빌드)

이 빌드는 Apple Developer ID 서명이 없습니다.
처음 실행할 때 macOS Gatekeeper가 \"확인되지 않은 개발자\" 경고를 띄울 수 있습니다.

**해결 방법 (둘 중 하나, 한 번만):**
1. Applications에서 \`WinMacKey.app\` **우클릭 → 열기 → 다시 \"열기\"** 클릭
2. 또는 터미널에서: \`xattr -dr com.apple.quarantine /Applications/WinMacKey.app\`

한 번 허용하면 이후 실행은 정상 동작합니다."

echo ""
echo "🎉 릴리스 v${VERSION} 완료!"
echo "   https://github.com/lee-minki/mac-windows-like-key/releases/tag/v${VERSION}"
