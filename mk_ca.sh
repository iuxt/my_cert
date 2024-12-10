#!/bin/bash

mkdir -p ca && cd "$_" || exit


# 创建私钥
if [ ! -f ca.key ]; then
    openssl genrsa -out ca.key 4096
else
    echo "ca.key 已存在"
fi


# 创建证书
if [ ! -f ca.crt ]; then
    openssl req -x509 -new -nodes -sha512 -days 36500 \
    -subj "/C=CN/ST=Shanghai/L=Shanghai/O=iuxt/OU=iuxt/CN=zhanglikun" \
    -key ca.key \
    -out ca.crt
else
    echo "ca.crt 已存在"
fi


# CA 的数据库文件
[ ! -f index.txt ] && touch index.txt


# crlnumber初始化
[ ! -f crlnumber ] && echo "01" > crlnumber


# crl.pem 吊销证书生成
cd ..
if [ ! -f ca/crl.pem ];then
    openssl ca -config openssl.cnf -cert ca/ca.crt -keyfile ca/ca.key -gencrl -out ca/crl.pem
fi
