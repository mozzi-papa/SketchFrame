#!/bin/sh
set -eu
umask 077
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
NAME='WindowSketch Local Signing'

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    IDENTITIES=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/"WindowSketch Local Signing"$/ { print $2 }')
    set -- $IDENTITIES
    if [ "$#" -eq 1 ]; then
        printf '%s\n' '기존 윈도우스케치 서명 인증서를 유지합니다.'
        exit 0
    fi
    printf '%s\n' '같은 이름의 인증서가 있지만 유효한 서명 인증서를 하나로 확인할 수 없습니다. 키체인에서 확인해 주세요.' >&2
    exit 1
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/windowsketch-signing.XXXXXX")
trap 'rm -rf "$WORK"' 0
cat > "$WORK/certificate.cnf" <<'EOF'
[req]
distinguished_name = subject
x509_extensions = signing
prompt = no
[subject]
CN = WindowSketch Local Signing
[signing]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
/usr/bin/openssl req -new -newkey rsa:2048 -nodes -x509 -sha256 -days 3650 \
    -config "$WORK/certificate.cnf" -keyout "$WORK/private-key.pem" -out "$WORK/certificate.pem" 2> "$WORK/generation.log"
WINDOWSKETCH_P12_PASSWORD=$(/usr/bin/openssl rand -hex 32)
export WINDOWSKETCH_P12_PASSWORD
/usr/bin/openssl pkcs12 -export -name "$NAME" -inkey "$WORK/private-key.pem" \
    -in "$WORK/certificate.pem" -out "$WORK/identity.p12" -passout env:WINDOWSKETCH_P12_PASSWORD
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$WINDOWSKETCH_P12_PASSWORD" -T /usr/bin/codesign
unset WINDOWSKETCH_P12_PASSWORD
# 현재 사용자의 코드 서명 정책에만 추가합니다.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/certificate.pem"
IDENTITIES=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/"WindowSketch Local Signing"$/ { print $2 }')
set -- $IDENTITIES
if [ "$#" -ne 1 ]; then
    printf '%s\n' '인증서 등록 후 서명 가능 상태를 확인하지 못했습니다. 키체인에서 확인해 주세요.' >&2
    exit 1
fi
printf '%s\n' '전용 인증서와 개인키를 로그인 키체인에 등록했습니다. 임시 키 파일은 삭제합니다.'
