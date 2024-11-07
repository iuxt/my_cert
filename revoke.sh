#!/bin/bash
set -euo pipefail

touch ca/index.txt

# crlnumber初始化
[ ! -f ca/crlnumber ] && echo "01" > ca/crlnumber

# 吊销指定证书
openssl ca  -config openssl.cnf -cert ca/ca.crt  -keyfile  ca/ca.key  -revoke ssl/"$1" 



# 吊销完成后，重新生成吊销列表，建议定期重新生成 CRL 文件，并在 Nginx 上重新加载配置
openssl ca -config openssl.cnf  -cert ca/ca.crt  -keyfile  ca/ca.key  -gencrl -out ca/crl.pem


