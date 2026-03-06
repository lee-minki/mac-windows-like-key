#!/bin/bash
# KarabinerHelper 빌드 스크립트
# Karabiner-DriverKit-VirtualHIDDevice 의존성을 다운로드하고 헬퍼 바이너리를 빌드합니다.
#
# 사용법: ./scripts/build_karabiner_helper.sh
# 요구사항: Xcode, xcodegen (brew install xcodegen)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HELPER_DIR="$PROJECT_ROOT/KarabinerHelper"
VENDOR_DIR="$HELPER_DIR/vendor"
KARABINER_REPO="https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice.git"
KARABINER_CLONE_DIR="/tmp/karabiner-driverkit-build"

echo "=== KarabinerHelper Build Script ==="
echo ""

# 1. xcodegen 확인
if ! command -v xcodegen &> /dev/null; then
    echo "❌ xcodegen이 설치되어 있지 않습니다."
    echo "   설치: brew install xcodegen"
    exit 1
fi

# 2. Karabiner 저장소 클론 (이미 있으면 pull)
echo "📥 Karabiner-DriverKit-VirtualHIDDevice 저장소 다운로드..."
if [ -d "$KARABINER_CLONE_DIR" ]; then
    echo "   기존 클론 발견, 업데이트 중..."
    cd "$KARABINER_CLONE_DIR"
    git pull --quiet 2>/dev/null || true
else
    git clone --depth 1 "$KARABINER_REPO" "$KARABINER_CLONE_DIR"
fi

# 3. Vendor 의존성 빌드 (Karabiner의 CMake vendor 시스템 사용)
echo "📦 Vendor 의존성 빌드..."
cd "$KARABINER_CLONE_DIR/vendor"
if [ ! -d "vendor/include" ]; then
    make
fi

# 4. 헤더 복사
echo "📋 헤더 파일 복사..."
mkdir -p "$VENDOR_DIR/include"

# Vendor 의존성 헤더 (vendor/vendor/include/)
if [ -d "$KARABINER_CLONE_DIR/vendor/vendor/include" ]; then
    cp -R "$KARABINER_CLONE_DIR/vendor/vendor/include/"* "$VENDOR_DIR/include/"
fi

# Karabiner 자체 헤더 (include/) — 같은 경로에 병합 (상호 참조 해결)
if [ -d "$KARABINER_CLONE_DIR/include" ]; then
    cp -R "$KARABINER_CLONE_DIR/include/"* "$VENDOR_DIR/include/"
fi

echo "   ✅ 헤더 복사 완료"

# 5. xcodegen으로 Xcode 프로젝트 생성
echo "🔧 Xcode 프로젝트 생성..."
cd "$HELPER_DIR"
xcodegen generate

# 6. 빌드
echo "🔨 KarabinerHelper 빌드..."
xcodebuild -configuration Release -alltargets SYMROOT="$HELPER_DIR/build" 2>&1 | tail -5

# 7. 결과 확인
BINARY="$HELPER_DIR/build/Release/KarabinerHelper"
if [ -f "$BINARY" ]; then
    echo ""
    echo "✅ 빌드 성공!"
    echo "   바이너리: $BINARY"
    echo ""
    echo "   테스트 실행 (Karabiner 드라이버 필요):"
    echo "   sudo $BINARY"
    echo ""
    
    echo "   release.sh 실행 시 자동으로 앱 번들에 포함됩니다."
else
    echo "❌ 빌드 실패"
    exit 1
fi
