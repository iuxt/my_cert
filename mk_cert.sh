#!/bin/bash
set -euo pipefail

source .env

mkdir -p ssl && cd "$_" || exit

if [ ! -f ca.crt ]; then
    echo "请先生成CA证书"
    exit 0
fi

[ ! -f "${HOST}".key ] && openssl genrsa -out "${HOST}".key 4096

[ ! -f "${HOST}".csr ] && \
openssl req -sha512 -new \
    -subj "/C=CN/ST=Shanghai/L=Shanghai/O=iuxt/OU=iuxt/CN=${HOST}" \
    -key "${HOST}".key \
    -out "${HOST}".csr


cat > v3.ext <<-EOF
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName=@SubjectAlternativeName

[ SubjectAlternativeName ]
DNS.1=${HOST}
DNS.2=*.${HOST}
DNS.3=localhost
IP.1=${IP_1}
IP.2=${IP_2}
IP.3=${IP_3}
EOF

[ ! -f "${HOST}".crt ] && \
openssl x509 -req -sha512 -days 3650 \
    -extfile v3.ext \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -in "${HOST}".csr \
    -out "${HOST}".crt
