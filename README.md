## 这是什么

这是一个小工具，可以生成自签名的证书，并在浏览器或程序中使用，纯`shell`脚本，调用`openssl`签发。

## 效果

![](https://static.zahui.fan/images/202411071641322.png)

![](https://static.zahui.fan/images/202411071641461.png)

![](https://static.zahui.fan/images/202411071641156.png)


## 首先制作CA证书

CA证书直接执行`./mk_ca.sh`即可，会在`ca`目录中生成 `ca.crt`(证书) `ca.key`(私钥) `ca.srl` 这几个文件，其中自己的操作系统需要信任`ca.crt`证书文件。

## 制作证书

执行 `./mk_cert.sh test.i.com` (将test.i.com换成你想要的域名)生成证书。

## 信任CA证书


参考: [制作和使用自签名证书](https://zahui.fan/posts/097e5b7c/) 里面的 **配置客户端信任 CA 证书** 章节


## 配置证书

### Nginx

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

---


## 创建用户证书

```bash
./mk_cert.sh zhangsan

# 将证书和私钥转换成p12格式，给windows用。p12 证书导入到证书管理器 个人 分类下
openssl pkcs12 -export -in zhangsan.crt -inkey zhangsan.key -out zhangsan.p12
```

## 配置证书吊销列表

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


## 吊销证书

```bash
./revoke.sh zhangsan
```

吊销完成后，需要把 ca/crl.pem 更新到nginx上并reload nginx才能生效。