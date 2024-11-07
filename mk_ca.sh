#!/bin/bash

mkdir -p ssl && cd "$_" || exit

[ ! -f ca.key ] && openssl genrsa -out ca.key 4096

[ ! -f ca.crt ] && \
openssl req -x509 -new -nodes -sha512 -days 36500 \
  -subj "/C=CN/ST=Shanghai/L=Shanghai/O=iuxt/OU=iuxt/CN=张理坤" \
  -key ca.key \
  -out ca.crt
