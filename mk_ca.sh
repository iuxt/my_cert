#!/bin/bash

#创建目录保存证书（可选）
mkdir -p ssl && cd "$_" || exit

openssl genrsa -out ca.key 4096


openssl req -x509 -new -nodes -sha512 -days 36500 \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=example/OU=Personal/CN=i.com" \
  -key ca.key \
  -out ca.crt
