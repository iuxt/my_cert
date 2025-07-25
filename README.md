## 这是什么

这是一个小工具，可以生成自签名的证书，并在浏览器或程序中使用，纯`shell`脚本，调用`openssl`签发。 常用的场景有两个，一个是自签名https证书，让浏览器或程序信任。一个是双向认证使用，用户带着客户端证书才能正常访问业务。

## 效果

![](https://s3.babudiu.com/iuxt/images/202411071641322.png)

![](https://s3.babudiu.com/iuxt/images/202411071641461.png)

![](https://s3.babudiu.com/iuxt/images/202411071641156.png)

## 首先制作CA证书

CA证书直接执行`./mk_ca.sh`即可，会在`ca`目录中生成 `ca.crt`(证书) `ca.key`(私钥) `ca.srl` 这几个文件，其中自己的操作系统需要信任`ca.crt`证书文件。

## 场景一、制作自签名https证书


### 制作证书

执行 `./mk_cert.sh test.i.com` (将test.i.com换成你想要的域名)生成证书。


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

# 将证书和私钥转换成p12格式，给windows用。p12 证书导入到证书管理器 个人 分类下
openssl pkcs12 -export -in zhangsan.crt -inkey zhangsan.key -out zhangsan.p12
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

## 使用Docker

如果你本地没有openssl或者版本兼容问题，可以直接使用我制作好的Docker版工具：

```bash
# 生成CA
docker run --rm -v ./:/certs/ iuxt/my_cert:latest sh ./mk_ca.sh

# 生成证书
docker run --rm -v ./:/certs/ iuxt/my_cert:latest sh ./mk_cert.sh test.example.com

# 吊销证书
# docker run --rm -v ./:/certs/ iuxt/my_cert:latest sh ./revoke.sh test.example.com
```
