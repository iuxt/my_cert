#!/bin/bash
set -euo pipefail

mkdir -p user

if [ ! -f ca/ca.crt ]; then
    echo "请先生成CA证书"
    exit 0
fi

[ ! -f "user/${1}".key ] && openssl genrsa -out "user/${1}".key 4096

[ ! -f "user/${1}".csr ] && \
openssl req -sha512 -new \
    -subj "/C=CN/ST=Shanghai/L=Shanghai/O=iuxt/OU=iuxt/CN=${1}" \
    -key "user/${1}".key \
    -out "user/${1}".csr


[ ! -f "user/${1}".crt ] && \
openssl x509 -req -sha512 -days 3650 \
    -CA ca/ca.crt -CAkey ca/ca.key -CAcreateserial \
    -in "user/${1}".csr \
    -out "user/${1}".crt
