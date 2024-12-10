#!/bin/bash
set -euo pipefail

mkdir -p ssl

if [ ! -f ca/ca.crt ]; then
    echo "请先生成CA证书"
    exit 0
fi

[ ! -f "ssl/${HOST}".key ] && openssl genrsa -out "ssl/${HOST}".key 4096

[ ! -f "ssl/${HOST}".csr ] && \
openssl req -sha512 -new \
    -subj "/C=CN/ST=Shanghai/L=Shanghai/O=iuxt/OU=iuxt/CN=${HOST}" \
    -reqexts SAN \
    -config <(cat openssl.cnf <(printf "\n[SAN]\nsubjectAltName=DNS:localhost,IP:127.0.0.1,DNS:${HOST}")) \
    -key "ssl/${HOST}".key \
    -out "ssl/${HOST}".csr


[ ! -f "ssl/${HOST}".crt ] && \
openssl x509 -req -sha512 -days 3650 \
    -extfile ssl/v3.ext \
    -CA ca/ca.crt -CAkey ca/ca.key -CAcreateserial \
    -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1,DNS:${HOST}") \
    -in "ssl/${HOST}".csr \
    -out "ssl/${HOST}".crt
