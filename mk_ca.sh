#!/bin/sh

set -eu
umask 077
cd -- "$(dirname -- "$0")"
. ./common.sh

[ "$#" -eq 0 ] || fail "用法：$0"
mkdir -p ca
secure_private_files
init_work_dir ca

# 已有 CA 时不能生成另一把私钥，否则会破坏已有证书的信任链。
if ! valid_key ca/ca.key; then
    if valid_cert ca/ca.crt; then
        fail "已有 CA 证书但私钥缺失或损坏，请恢复原私钥"
    fi
    "$OPENSSL" ecparam -genkey -name prime256v1 -out "$work_dir/ca.key"
    "$OPENSSL" pkey -in "$work_dir/ca.key" -noout
    mv -f -- "$work_dir/ca.key" ca/ca.key
fi

if ! valid_cert ca/ca.crt; then
    "$OPENSSL" req -x509 -new -nodes -sha512 -days 36500 \
        -config openssl.cnf -extensions v3_ca \
        -subj "/CN=iuxt Root CA" \
        -key ca/ca.key -out "$work_dir/ca.crt"
    "$OPENSSL" verify -x509_strict -CAfile "$work_dir/ca.crt" "$work_dir/ca.crt"
    mv -f -- "$work_dir/ca.crt" ca/ca.crt
fi
require_ca

if [ ! -f ca/index.txt ]; then
    touch ca/index.txt
fi
if [ ! -s ca/crlnumber ]; then
    printf '01\n' > ca/crlnumber
fi
if ! "$OPENSSL" crl -in ca/crl.pem -noout >/dev/null 2>&1; then
    generate_crl
fi

printf 'CA 已就绪：ca/ca.crt\n'
