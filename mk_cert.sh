#!/bin/bash
set -euo pipefail

mkdir -p ssl

if [ ! -f ca/ca.crt ]; then
    echo "请先生成CA证书"
    exit 0
fi

[ ! -f "ssl/${1}".key ] && openssl genrsa -out "ssl/${1}".key 4096

[ ! -f "ssl/${1}".csr ] && \
openssl req -sha512 -new \
    -subj "/C=CN/ST=Shanghai/L=Shanghai/O=iuxt/OU=iuxt/CN=${1}" \
    -reqexts SAN \
    -config <(cat openssl.cnf <(printf "\n[SAN]\nsubjectAltName=DNS:localhost,IP:127.0.0.1,DNS:${1}")) \
    -key "ssl/${1}".key \
    -out "ssl/${1}".csr


[ ! -f "ssl/${1}".crt ] && \
openssl x509 -req -sha512 -days 3650 \
    -extfile ssl/v3.ext \
    -CA ca/ca.crt -CAkey ca/ca.key -CAcreateserial \
    -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1,DNS:${1}") \
    -in "ssl/${1}".csr \
    -out "ssl/${1}".crt
