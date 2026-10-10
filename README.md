## 这是什么

这是一个小工具，可以生成自签名的证书，并在浏览器或程序中使用，纯`shell`脚本，调用`openssl`签发。 常用的场景有两个，一个是自签名https证书，让浏览器或程序信任。一个是双向认证使用，用户带着客户端证书才能正常访问业务。

## 效果

![](https://s3.babudiu.com/iuxt/images/202411071641322.png)

![](https://s3.babudiu.com/iuxt/images/202411071641461.png)

![](https://s3.babudiu.com/iuxt/images/202411071641156.png)

## 首先制作CA证书

CA证书直接执行`./mk_ca.sh`即可，会在`ca`目录中生成 `ca.crt`(证书)、`ca.key`(私钥)、吊销数据库和 `crl.pem`(吊销列表)。自己的操作系统需要信任`ca.crt`证书文件。签发使用随机序列号，不依赖共享的 `ca.srl` 文件。

脚本支持 OpenSSL 和 macOS 自带 LibreSSL，也可以通过 `OPENSSL=/path/to/openssl ./mk_ca.sh` 指定可执行文件。私钥和 P12 文件使用 `0600` 权限；运行脚本时也会收紧已有文件的权限。

## 场景一、制作自签名https证书


### 制作证书

执行 `./mk_cert.sh test.i.com` (将test.i.com换成你想要的域名)生成证书。

证书、私钥、CSR 和 P12 文件保存在 `ssl/` 目录中。首次生成 P12 时需要输入并确认导出密码；文件齐全时重复执行会成功返回，不会再次询问密码。普通名称支持英文字母、数字、点、下划线和连字符，不能以点或连字符开头；IPv6 地址也可以直接使用。

脚本会区分域名、IP 地址和客户端用户名：

```bash
./mk_cert.sh test.example.com           # 域名：DNS SAN，包含该域名及其通配符
./mk_cert.sh 192.0.2.1                  # IPv4：IP SAN，不添加 IP 的 DNS 项或通配符
./mk_cert.sh '2001:db8::1'              # IPv6：IP SAN，使用不带方括号、区域标识的地址
./mk_cert.sh user_name                  # 用户名：写入 CN，不添加 SAN
./mk_cert.sh --client john.doe          # 带点的用户名：显式选择客户端身份
./mk_cert.sh --server intranet          # 单标签主机名：显式选择服务器身份
```

默认将 IPv4/IPv6、`localhost` 和不含下划线的带点名称作为服务器身份；其余名称作为客户端用户名。可用 `--server` 或 `--client` 明确指定身份类型和 SAN 规则；EKU 仍包含 `serverAuth` 和 `clientAuth`。服务器域名会校验标签格式和长度，IP 会校验地址格式；无效输入会在生成私钥前报错。IPv6 文件名保留冒号，吊销时使用原地址即可。

CA 和终端证书会经过严格 X.509 校验。生成失败时临时文件会被清理，空文件或无法解析的证书、CSR 会在重试时重新生成。P12 导出成功后才保存新证书。


### 服务器配置证书，以nginx举例

Nginx配置证书，只需要把 `证书.key` 和 `证书.crt` 配置到Nginx中即可。

```conf
server {
        listen 443 ssl;
        server_name localhost;
        ssl_certificate ssl/server.crt;         # 配置证书位置
        ssl_certificate_key ssl/server.key;     # 配置秘钥位置

        ssl_session_cache shared:SSL:1m;
        ssl_session_timeout  10m;
        ssl_ciphers PROFILE=SYSTEM;
        ssl_prefer_server_ciphers on;

        root html;
        index index.html;
        location / {
                try_files $uri $uri/ =404;
        }
}

```

### 客户端信任CA证书

参考: [制作和使用自签名证书](https://zahui.fan/posts/097e5b7c/) 里面的 **配置客户端信任 CA 证书** 章节



## 场景二、双向认证使用

### 给用户制作证书

```bash
./mk_cert.sh zhangsan

# 脚本已生成 ssl/zhangsan.p12，可导入 Windows 证书管理器的“个人”分类。
# 如需另行导出：
openssl pkcs12 -export -in ssl/zhangsan.crt -inkey ssl/zhangsan.key -out ssl/zhangsan.p12
```

### 配置证书吊销列表,以Nginx为例

```conf
server {
    listen 443 ssl;
    server_name example.com;

    ssl_certificate /path/to/your/server.crt;
    ssl_certificate_key /path/to/your/server.key;

    ssl_client_certificate /path/to/your/ca.crt;        # 配置 CA 证书，用于验证客户端证书的签发者
    ssl_verify_client on;                               # 启用客户端证书验证
    ssl_crl /path/to/your/crl.pem;                      # 配置 CRL 文件路径，用于检查吊销的证书

    location / {
        root /var/www/html;
        index index.html;
    }
}
```


### 吊销证书

如果不想让用户访问，可以吊销他的证书。

```bash
./revoke.sh zhangsan
```

吊销完成后，需要把 ca/crl.pem 更新到nginx上并reload nginx才能生效。

### 定期更新crl

吊销列表有默认有效期的，就算你的CA签了100年，证书签了10年，吊销证书到期没有更新，服务器也会拒绝客户端访问的。所以需要在crontab增加一个定期更新crl的任务。

```bash
0 1 * * * /root/my_cert/update_crl.sh >> /root/update_crl.log 2>&1
```

或者你也可以在 `openssl.cnf` 配置文件中，把 `default_crl_days` 给设置大一点。

`update_crl.sh` 默认只更新本地 `ca/crl.pem`。如需复制到 Nginx 并 reload，可在参数中指定目标文件和命令（支持命令参数）：

```bash
./update_crl.sh /etc/nginx/ssl/crl.pem nginx -s reload

# 保留原来 nebula 的部署方式，使用实际的绝对路径：
./update_crl.sh /root/nebula/nginx/ssl/crl.pem /root/nebula/nginx/reload.py
```

相对目标路径以仓库目录为基准。CRL 生成失败会保留原本的本地文件；复制失败时不会执行 reload，复制或 reload 失败都会返回非零状态。

## 旧证书迁移

旧脚本生成的证书可能缺少必要扩展。新版会报错提示迁移，不会自动替换可解析的旧 CA 或终端证书。迁移前请将整个 `ca/` 和 `ssl/` 目录备份到仓库外的安全位置。

- CA 缺少扩展时，移走 `ca/ca.crt` 和 `ca/crl.pem`，保留原 `ca/ca.key`、`ca/index.txt` 和 `ca/crlnumber`，然后运行 `./mk_ca.sh`。新的 CA 证书需要重新导入客户端信任库。
- 终端证书未通过严格校验时，移走对应的 `ssl/<名称>.crt` 和 `ssl/<名称>.p12`，保留私钥，再运行 `./mk_cert.sh <名称>`，并重新部署或分发证书。
- 旧用户名证书包含 SAN，或旧 IP 证书把地址写成 DNS SAN 时，同样移走对应 `.crt` 和 `.p12` 后重新签发。切换客户端和服务器身份时也需要重新签发。旧 CSR 会在重签时按新规则重新生成。带点用户名使用 `--client`，单标签服务器主机名使用 `--server`。

重新签发的终端证书使用新的序列号，旧证书的吊销记录不会自动吊销新证书。不要重签仍需禁止访问的用户。已有证书的私钥丢失或损坏时，脚本会停止，请先恢复原私钥。

## 使用Docker

如果你本地没有openssl或者版本兼容问题，可以直接使用我制作好的Docker版工具：

```bash
# 根据当前仓库构建镜像：
docker build -t my_cert:local .

# 生成CA
docker run --rm -v "$PWD:/certs" my_cert:local sh ./mk_ca.sh

# 生成证书，-it 用于输入 P12 导出密码
docker run --rm -it -v "$PWD:/certs" my_cert:local sh ./mk_cert.sh test.example.com

# 吊销证书
docker run --rm -v "$PWD:/certs" my_cert:local sh ./revoke.sh test.example.com
```

## 验证修改

运行 `python3 -m unittest discover -s tests -v`。测试在临时目录中生成证书，不会修改仓库中的 CA 和私钥；会验证本机可用的 OpenSSL/LibreSSL。
