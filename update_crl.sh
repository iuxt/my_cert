#!/bin/sh

set -eu
umask 077
cd -- "$(dirname -- "$0")"
. ./common.sh

secure_private_files
[ -d ca ] || fail "请先生成 CA：./mk_ca.sh"
init_work_dir ca
require_ca
generate_crl

# 默认只更新本地 CRL；传入目标路径及命令时才执行部署和 reload。
if [ "$#" -gt 0 ]; then
    destination=$1
    shift
    cp -- ca/crl.pem "$destination"
    if [ "$#" -gt 0 ]; then
        "$@"
    fi
fi
printf 'CRL 已更新：ca/crl.pem\n'
