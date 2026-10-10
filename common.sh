# 由各入口脚本加载；OPENSSL 可以指定其他 OpenSSL/LibreSSL 可执行文件。
OPENSSL=${OPENSSL:-openssl}

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

validate_name() {
    case "$1" in
        *:*)
            is_ip_address "$1" || fail "无效的 IPv6 地址：$1"
            ;;
        ''|.*|-*|*[!a-zA-Z0-9._-]*)
            fail "名称只能包含英文字母、数字、点、下划线和连字符，且不能以点或连字符开头"
            ;;
    esac
}

is_ip_address() {
    # POSIX awk 校验 IPv4/IPv6，包括压缩 IPv6 和末尾嵌入 IPv4 的写法。
    awk -v address="$1" '
        function ipv4(value, octets, count, i) {
            count = split(value, octets, "\\.")
            if (count != 4) return 0
            for (i = 1; i <= count; i++) {
                if (octets[i] !~ /^[0-9]+$/ || length(octets[i]) > 3 ||
                    (length(octets[i]) > 1 && substr(octets[i], 1, 1) == "0") ||
                    octets[i] + 0 > 255) return 0
            }
            return 1
        }
        function groups(value, labels, count, i) {
            if (value == "") return 0
            count = split(value, labels, ":")
            for (i = 1; i <= count; i++) {
                if (labels[i] !~ /^[0-9a-fA-F]+$/ || length(labels[i]) > 4) return -100
            }
            return count
        }
        BEGIN {
            if (index(address, ":") == 0) exit !ipv4(address)
            if (index(address, ".") != 0) {
                tail = address
                sub(/^.*:/, "", tail)
                if (!ipv4(tail)) exit 1
                sub(/[^:]+$/, "0:0", address)
            }
            if (address ~ /:::/) exit 1
            count = split(address, halves, "::")
            if (count == 1) exit groups(address) != 8
            if (count != 2) exit 1
            left = groups(halves[1])
            right = groups(halves[2])
            exit !(left >= 0 && right >= 0 && left + right < 8)
        }
    '
}

is_dns_name() {
    awk -v domain="$1" '
        BEGIN {
            if (domain == "" || length(domain) > 253) exit 1
            count = split(domain, labels, "\\.")
            for (i = 1; i <= count; i++) {
                if (length(labels[i]) > 63 || labels[i] !~ /^[A-Za-z0-9-]+$/ ||
                    labels[i] ~ /^-/ || labels[i] ~ /-$/) exit 1
            }
        }
    '
}

secure_private_files() {
    for private_file in ca/*.key ssl/*.key ssl/*.p12; do
        if [ -f "$private_file" ]; then
            chmod 600 "$private_file"
        fi
    done
}

init_work_dir() {
    work_dir=$(mktemp -d "$1/.tmp.XXXXXX")
    trap 'rm -rf -- "$work_dir"' 0
    trap 'exit 1' HUP INT TERM
}

valid_key() {
    [ -s "$1" ] && "$OPENSSL" pkey -in "$1" -noout >/dev/null 2>&1
}

valid_cert() {
    [ -s "$1" ] && "$OPENSSL" x509 -in "$1" -noout >/dev/null 2>&1
}

public_keys_match() {
    "$OPENSSL" pkey -in "$1" -pubout > "$work_dir/key.pub" || return 1
    "$OPENSSL" "$2" -in "$3" -pubkey -noout > "$work_dir/cert.pub" || return 1
    cmp -s "$work_dir/key.pub" "$work_dir/cert.pub"
}

check_ca_certificate() {
    ca_text=$("$OPENSSL" x509 -in ca/ca.crt -noout -text) || fail "CA 证书无法读取"
    case "$ca_text" in
        *"X509v3 Subject Key Identifier:"*) ;;
        *) fail "现有 CA 缺少 Subject Key Identifier，请参考 README 的旧证书迁移说明" ;;
    esac
    case "$ca_text" in
        *"X509v3 Key Usage:"*) ;;
        *) fail "现有 CA 缺少 Key Usage，请参考 README 的旧证书迁移说明" ;;
    esac
    "$OPENSSL" verify -x509_strict -CAfile ca/ca.crt ca/ca.crt >/dev/null \
        || fail "CA 证书未通过严格校验，请参考 README 的旧证书迁移说明"
}

require_ca() {
    valid_key ca/ca.key && valid_cert ca/ca.crt || fail "请先生成有效的 CA 证书和私钥：./mk_ca.sh"
    public_keys_match ca/ca.key x509 ca/ca.crt || fail "CA 证书与私钥不匹配，请恢复正确的私钥"
    check_ca_certificate
}

check_leaf_certificate() {
    leaf_text=$("$OPENSSL" x509 -in "$1" -noout -text) || fail "证书无法读取：$1"
    # LibreSSL 的严格模式不会检查 AKI，显式检查以保持各版本行为一致。
    case "$leaf_text" in
        *"X509v3 Authority Key Identifier:"*) ;;
        *) fail "现有证书缺少 Authority Key Identifier，请参考 README 的旧证书迁移说明" ;;
    esac
    "$OPENSSL" verify -x509_strict -CAfile ca/ca.crt "$1" \
        || fail "现有证书未通过严格校验，请参考 README 的旧证书迁移说明"
}

generate_crl() {
    "$OPENSSL" ca -config openssl.cnf -cert ca/ca.crt -keyfile ca/ca.key \
        -gencrl -out "$work_dir/crl.pem"
    "$OPENSSL" crl -in "$work_dir/crl.pem" -noout
    mv -f -- "$work_dir/crl.pem" ca/crl.pem
}
