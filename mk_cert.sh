#!/bin/bash
set -euo pipefail

source .env

mkdir -p ssl

if [ ! -f ca/ca.crt ]; then
    echo "请先生成CA证书"
    exit 0
fi

[ ! -f "ssl/${HOST}".key ] && openssl genrsa -out "ssl/${HOST}".key 4096

[ ! -f "ssl/${HOST}".csr ] && \
openssl req -sha512 -new \
    -subj "/C=CN/ST=Shanghai/L=Shanghai/O=iuxt/OU=iuxt/CN=${HOST}" \
    -key "ssl/${HOST}".key \
    -out "ssl/${HOST}".csr


cat > ssl/v3.ext <<-EOF
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

[ ! -f "ssl/${HOST}".crt ] && \
openssl x509 -req -sha512 -days 3650 \
    -extfile ssl/v3.ext \
    -CA ca/ca.crt -CAkey ca/ca.key -CAcreateserial \
    -in "ssl/${HOST}".csr \
    -out "ssl/${HOST}".crt
