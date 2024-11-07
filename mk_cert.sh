#!/bin/bash

mkdir -p ssl && cd "$_" || exit

openssl genrsa -out i.com.key 4096

openssl req -sha512 -new \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=example/OU=Personal/CN=i.com" \
    -key i.com.key \
    -out i.com.csr


cat > v3.ext <<-EOF
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName=@SubjectAlternativeName

[ SubjectAlternativeName ]
DNS.1=i.com
DNS.2=*.i.com
DNS.3=localhost
IP.1=127.0.0.1
IP.2=10.0.0.30
IP.3=10.0.0.3
EOF


openssl x509 -req -sha512 -days 3650 \
    -extfile v3.ext \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -in i.com.csr \
    -out i.com.crt
