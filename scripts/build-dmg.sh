#!/bin/bash
# WinMac Key DMG 빌드 스크립트
# Usage: ./build-dmg.sh [version]

set -e

VERSION=${1:-"1.0.0"}
APP_NAME="WinMacKey"
BUILD_DIR="build"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

echo "🔨 Building WinMac Key v${VERSION}..."

# 이전 빌드 정리
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Release 빌드
echo "📦 Building Release..."
xcodebuild -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    archive

# 앱 추출 (Export 생략하고 Archive에서 직접 사용 - 서명 문제 회피)
echo "📱 Extracting App from Archive..."
APP_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app"

# ExportOptions.plist 사용 안 함
# xcodebuild -exportArchive ...

# DMG 생성
echo "💿 Creating DMG..."
if command -v create-dmg &> /dev/null; then
    # create-dmg 사용 (brew install create-dmg)
    create-dmg \
        --volname "${APP_NAME}" \
        --volicon "${APP_PATH}/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 150 185 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 450 185 \
        "${BUILD_DIR}/${DMG_NAME}" \
        "${APP_PATH}"
else
    # 기본 hdiutil 사용
    echo "⚠️  create-dmg not found, using hdiutil..."
    
    STAGING_DIR="${BUILD_DIR}/dmg-staging"
    mkdir -p "${STAGING_DIR}"
    cp -r "${APP_PATH}" "${STAGING_DIR}/"
    ln -s /Applications "${STAGING_DIR}/Applications"
    
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "${STAGING_DIR}" \
        -ov -format UDZO \
        "${BUILD_DIR}/${DMG_NAME}"
    
    rm -rf "${STAGING_DIR}"
fi

echo "✅ DMG created: ${BUILD_DIR}/${DMG_NAME}"
echo ""
echo "📤 To upload to GitHub Releases:"
echo "   1. Go to https://github.com/lee-minki/winmac-key/releases/new"
echo "   2. Tag: v${VERSION}"
echo "   3. Upload: ${BUILD_DIR}/${DMG_NAME}"
