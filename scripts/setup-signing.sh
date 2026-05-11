#!/bin/bash
# Self-signed code signing identity 생성 스크립트
#
# 한 번 실행하면 로컬 login 키체인에 "WinMacKey Self-Signed" 인증서 + private key가
# 추가되고, 이후 ./scripts/release.sh 가 자동으로 이 identity로 서명합니다.
#
# Apple Developer Program 없이도 손쉬운 사용(Accessibility) 권한이 빌드 간 영속됩니다.
# 같은 cert로 서명된 모든 빌드는 macOS TCC가 동일 앱으로 인식하기 때문입니다.
#
# Note: 이 identity는 self-signed라 macOS Keychain Access GUI나
#       `security find-identity -p codesigning` 에서는 보이지 않을 수 있습니다.
#       (Apple이 trusted CA chain을 요구하기 때문)
#       그러나 `codesign -s "WinMacKey Self-Signed"` 는 정상 동작합니다.
#
# 팀원과 공유: 동일 identity를 다른 머신에서도 쓰려면
#   security export -k login.keychain-db -t identities -f pkcs12 -P '<password>' -o cert.p12
# 로 export 후 안전한 채널(1Password 등)로 전달.
#
# 제거:
#   security delete-certificate -c "WinMacKey Self-Signed"

set -e

IDENTITY="${1:-WinMacKey Self-Signed}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
TMPDIR="$(mktemp -d)"
trap "rm -rf '$TMPDIR'" EXIT

echo "🔐 Code signing identity 생성"
echo "   Identity: $IDENTITY"
echo "   Keychain: $KEYCHAIN"
echo ""

# 이미 동작 가능한 cert가 있는지 확인 (codesign 테스트로 검증)
verify_identity() {
    local test_file="$1"
    cp /bin/ls "$test_file"
    if codesign --force -s "$IDENTITY" "$test_file" 2>/dev/null; then
        # signature가 self-signed authority로 발급됐는지 확인
        if codesign -dvvv "$test_file" 2>&1 | grep -q "Authority=$IDENTITY"; then
            return 0
        fi
    fi
    return 1
}

if verify_identity "${TMPDIR}/check"; then
    echo "✅ 이미 동작 가능한 identity가 있습니다. 별도 작업 불필요."
    exit 0
fi

# openssl 가용성
if ! command -v openssl >/dev/null 2>&1; then
    echo "❌ openssl이 필요합니다. brew install openssl"
    exit 1
fi

# OpenSSL config — Code Signing EKU 포함
cat > "${TMPDIR}/openssl.cnf" <<EOF
[req]
distinguished_name = req_dn
x509_extensions = v3_ext
prompt = no

[req_dn]
CN = ${IDENTITY}

[v3_ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

echo "🔑 RSA 2048 키 + X.509 인증서 생성 중..."
openssl req -new -x509 -newkey rsa:2048 \
    -keyout "${TMPDIR}/key.pem" \
    -out "${TMPDIR}/cert.pem" \
    -days 3650 \
    -nodes \
    -config "${TMPDIR}/openssl.cnf" \
    2>/dev/null

echo "📦 PKCS#12 번들 생성 (macOS 호환 SHA-1 MAC + 3DES)..."
P12_PASS="$(openssl rand -hex 8)"
openssl pkcs12 -export \
    -in "${TMPDIR}/cert.pem" \
    -inkey "${TMPDIR}/key.pem" \
    -out "${TMPDIR}/bundle.p12" \
    -name "${IDENTITY}" \
    -password "pass:${P12_PASS}" \
    -macalg sha1 \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    2>/dev/null

echo "🔓 키체인에 import 중..."
security import "${TMPDIR}/bundle.p12" \
    -k "$KEYCHAIN" \
    -P "${P12_PASS}" \
    -A \
    >/dev/null 2>&1 || {
    echo "❌ Import 실패 (security import 비정상 종료)"
    exit 1
}

sleep 0.3

# 검증 — codesign 실제 동작 테스트
if verify_identity "${TMPDIR}/verify"; then
    echo ""
    echo "✅ 완료 — '$IDENTITY' identity가 동작합니다."
    echo ""
    echo "검증:"
    echo "   /bin/ls 테스트 파일에 codesign 실행 → Authority=$IDENTITY ✓"
    echo ""
    echo "이제 다음 빌드부터는 자동으로 이 identity로 서명됩니다:"
    echo "   ./scripts/release.sh <version>"
else
    echo ""
    echo "❌ Import는 됐지만 codesign 동작이 확인되지 않습니다."
    echo ""
    echo "수동 검증:"
    echo "   cp /bin/ls /tmp/testsign && codesign -s '$IDENTITY' /tmp/testsign"
    echo "   codesign -dvvv /tmp/testsign"
    exit 1
fi
