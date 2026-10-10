#!/bin/sh

set -eu
umask 077
cd -- "$(dirname -- "$0")"
. ./common.sh

[ "$#" -eq 1 ] || fail "用法：$0 <域名或用户名>"
validate_name "$1"
secure_private_files
[ -d ca ] || fail "请先生成 CA：./mk_ca.sh"
init_work_dir ca
require_ca
valid_cert "ssl/$1.crt" || fail "证书不存在或损坏：ssl/$1.crt"

"$OPENSSL" ca -config openssl.cnf -cert ca/ca.crt -keyfile ca/ca.key -revoke "ssl/$1.crt"
generate_crl
printf '证书已吊销，CRL 已更新：ca/crl.pem\n'
