#!/bin/sh

set -eu
umask 077
cd -- "$(dirname -- "$0")"
. ./common.sh

mode=auto
if [ "$#" -eq 2 ]; then
    case "$1" in
        --server) mode=server ;;
        --client) mode=client ;;
        *) fail "用法：$0 [--server|--client] <域名、IP 或用户名>" ;;
    esac
    shift
fi
[ "$#" -eq 1 ] || fail "用法：$0 [--server|--client] <域名、IP 或用户名>"
name=$1
validate_name "$name"

san=
if [ "$mode" = auto ]; then
    case "$name" in
        *:*|localhost) mode=server ;;
        *_*) mode=client ;;
        *.*) mode=server ;;
        *) mode=client ;;
    esac
fi
if [ "$mode" = server ]; then
    if is_ip_address "$name"; then
        san="DNS:localhost,IP:127.0.0.1,IP:$name"
        identity_type=ip
    else
        case "$name" in
            *:*|*[!0-9.]*) ;;
            *) fail "无效的 IPv4 地址：$name" ;;
        esac
        dns_name=${name%.}
        is_dns_name "$dns_name" || fail "无效的 DNS 主机名：$name"
        san="DNS:localhost,IP:127.0.0.1,DNS:$dns_name"
        if [ "${#dns_name}" -le 251 ]; then
            san="$san,DNS:*.$dns_name"
        fi
        identity_type=dns
    fi
else
    identity_type=client
fi

mkdir -p ssl
secure_private_files
init_work_dir ssl
require_ca

key="ssl/$name.key"
csr="ssl/$name.csr"
cert="ssl/$name.crt"
p12="ssl/$name.p12"

if ! valid_key "$key"; then
    if valid_cert "$cert"; then
        fail "已有证书但私钥缺失或损坏，请恢复原私钥"
    fi
    "$OPENSSL" ecparam -genkey -name prime256v1 -out "$work_dir/cert.key"
    "$OPENSSL" pkey -in "$work_dir/cert.key" -noout
    mv -f -- "$work_dir/cert.key" "$key"
fi

# 用户名只写入 CN；服务器的 DNS/IP SAN 同时用于 CSR 和签发。
cat openssl.cnf > "$work_dir/openssl.cnf"
if [ -n "$san" ]; then
    printf '\n[SAN]\nsubjectAltName=%s\n\n[usr_cert]\nsubjectAltName=%s\n' \
        "$san" "$san" >> "$work_dir/openssl.cnf"
fi

if ! valid_cert "$cert" \
    || ! "$OPENSSL" req -in "$csr" -noout -verify >/dev/null 2>&1 \
    || ! public_keys_match "$key" req "$csr"; then
    set -- "$OPENSSL" req -sha512 -new -subj "/CN=$name" \
        -config "$work_dir/openssl.cnf" -key "$key" -out "$work_dir/cert.csr"
    if [ -n "$san" ]; then
        set -- "$@" -reqexts SAN
    fi
    "$@"
    "$OPENSSL" req -in "$work_dir/cert.csr" -noout -verify
    mv -f -- "$work_dir/cert.csr" "$csr"
fi

cert_input=$cert
new_cert=0
if ! valid_cert "$cert"; then
    # 随机序列号避免并行签发时读写共享 ca.srl 文件。
    serial=$("$OPENSSL" rand -hex 16)
    "$OPENSSL" x509 -req -sha512 -days 3650 -set_serial "0x$serial" \
        -CA ca/ca.crt -CAkey ca/ca.key \
        -extfile "$work_dir/openssl.cnf" -extensions usr_cert \
        -in "$csr" -out "$work_dir/cert.crt"
    cert_input="$work_dir/cert.crt"
    new_cert=1
fi
public_keys_match "$key" x509 "$cert_input" || fail "证书与私钥不匹配，请恢复正确的私钥"
check_leaf_certificate "$cert_input"
case "$identity_type:$leaf_text" in
    client:*"X509v3 Subject Alternative Name:"*)
        fail "现有客户端证书仍含 SAN，请备份并移走对应 .crt 和 .p12 后重新签发"
        ;;
    ip:*"DNS:$name"*)
        fail "现有 IP 证书使用了 DNS SAN，请备份并移走对应 .crt 和 .p12 后重新签发"
        ;;
    dns:*"X509v3 Subject Alternative Name:"*|ip:*"X509v3 Subject Alternative Name:"*) ;;
    dns:*|ip:*)
        fail "现有服务器证书缺少 SAN，请备份并移走对应 .crt 和 .p12 后重新签发"
        ;;
esac

if [ "$new_cert" -eq 1 ] \
    || [ ! -s "$p12" ] \
    || ! "$OPENSSL" asn1parse -inform DER -in "$p12" -noout >/dev/null 2>&1; then
    "$OPENSSL" pkcs12 -export -in "$cert_input" -inkey "$key" -out "$work_dir/cert.p12"
    if [ "$new_cert" -eq 1 ]; then
        mv -f -- "$work_dir/cert.crt" "$cert"
    fi
    mv -f -- "$work_dir/cert.p12" "$p12"
fi

printf '证书已就绪：%s\n' "$cert"
