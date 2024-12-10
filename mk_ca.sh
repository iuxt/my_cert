#!/bin/bash

mkdir -p ca && cd "$_" || exit

if [ ! -f ca.key ]; then
    openssl genrsa -out ca.key 4096
else
    echo "ca.key 已存在"
fi


if [ ! -f ca.crt ]; then
    openssl req -x509 -new -nodes -sha512 -days 36500 \
    -subj "/C=CN/ST=Shanghai/L=Shanghai/O=iuxt/OU=iuxt/CN=zhanglikun" \
    -key ca.key \
    -out ca.crt
else
    echo "ca.crt 已存在"
fi
