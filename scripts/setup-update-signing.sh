#!/bin/bash
# Ed25519 update-signing keypair 생성 스크립트
#
# 한 번 실행하면:
#   1. Ed25519 private key를 ~/.config/winmackey/update-signing.key 에 저장 (mode 0600)
#   2. Public key를 WinMacKey/Services/UpdateService.swift 의
#      updateSigningPublicKeyBase64 상수에 임베드
#
# Apple Developer Program 없이도 자동 업데이트 다운로드 자산의 무결성과 발신자 인증을 보장합니다.
# release.sh 가 zip/dmg를 빌드 후 private key로 서명하고, 앱은 임베드된 public key로 검증합니다.
#
# 팀원과 공유: ~/.config/winmackey/update-signing.key 를 1Password 등 안전한 채널로 전달.
# 그 머신에서도 동일 경로에 저장하면 release.sh가 자동 사용.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_DIR="${HOME}/.config/winmackey"
KEY_PATH="${KEY_DIR}/update-signing.key"
UPDATE_SERVICE="${REPO_ROOT}/WinMacKey/Services/UpdateService.swift"
PLACEHOLDER='updateSigningPublicKeyBase64'

echo "🔐 Update-signing Ed25519 keypair 생성"
echo "   Private key: $KEY_PATH"
echo "   Embedded in: $UPDATE_SERVICE"
echo ""

mkdir -p "$KEY_DIR"
chmod 0700 "$KEY_DIR"

if [ -f "$KEY_PATH" ]; then
    echo "⚠️  이미 존재하는 키: $KEY_PATH"
    echo ""
    read -p "덮어쓰시겠습니까? 기존 키로 서명된 모든 릴리스는 검증 실패합니다. [y/N] " ans
    if [ "$ans" != "y" ] && [ "$ans" != "Y" ]; then
        echo "취소됨"
        exit 0
    fi
fi

# Ed25519는 LibreSSL 3.3.6 (Apple 기본) 에서 미지원 — OpenSSL 3.x (brew) 우선 사용
OPENSSL_BIN=""
for candidate in \
    "/opt/homebrew/opt/openssl@3/bin/openssl" \
    "/opt/homebrew/bin/openssl" \
    "/usr/local/opt/openssl@3/bin/openssl" \
    "/usr/local/bin/openssl"
do
    if [ -x "$candidate" ]; then
        if "$candidate" version 2>/dev/null | grep -qE "^OpenSSL 3\."; then
            OPENSSL_BIN="$candidate"
            break
        fi
    fi
done

if [ -z "$OPENSSL_BIN" ]; then
    echo "❌ OpenSSL 3.x가 필요합니다 (Apple 기본 LibreSSL은 Ed25519 미지원)."
    echo "   설치: brew install openssl@3"
    exit 1
fi

echo "   OpenSSL: $($OPENSSL_BIN version)"

if ! "$OPENSSL_BIN" genpkey -algorithm ed25519 -out "$KEY_PATH" 2>/dev/null; then
    echo "❌ Ed25519 키 생성 실패"
    exit 1
fi
chmod 0600 "$KEY_PATH"

# Public key를 raw 32바이트 → base64 변환
# Ed25519 SubjectPublicKeyInfo DER의 끝 32바이트가 raw public key
PUB_B64="$("$OPENSSL_BIN" pkey -in "$KEY_PATH" -pubout -outform DER 2>/dev/null | tail -c 32 | base64)"

if [ -z "$PUB_B64" ]; then
    echo "❌ Public key 추출 실패"
    exit 1
fi

# UpdateService.swift 의 placeholder 라인을 찾아 교체
# 형식: static let updateSigningPublicKeyBase64: String = "..."
if ! grep -q "$PLACEHOLDER" "$UPDATE_SERVICE"; then
    echo "❌ $UPDATE_SERVICE 에 '$PLACEHOLDER' 라인이 없습니다."
    echo "   UpdateService.swift 가 update-signing 통합 후 코드인지 확인해주세요."
    exit 1
fi

# sed로 base64 값만 교체 (라인 전체를 재생성)
TMP="$(mktemp)"
awk -v pubkey="$PUB_B64" '
    /static let updateSigningPublicKeyBase64: String = / {
        match($0, /^[[:space:]]*/)
        indent = substr($0, RSTART, RLENGTH)
        printf "%sstatic let updateSigningPublicKeyBase64: String = \"%s\"\n", indent, pubkey
        next
    }
    { print }
' "$UPDATE_SERVICE" > "$TMP"
mv "$TMP" "$UPDATE_SERVICE"

echo "✅ 완료"
echo ""
echo "   Private key: $KEY_PATH (mode 0600)"
echo "   Public key:  ${PUB_B64}"
echo "   임베드 위치: $UPDATE_SERVICE"
echo ""
echo "다음 빌드부터 release.sh 가 자동으로 ZIP/DMG에 .sig 파일을 동봉합니다."
echo "앱은 자동 업데이트 시 임베드된 public key로 검증합니다."
