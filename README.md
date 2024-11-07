## 这是什么

这是一个小工具，可以生成自签名的证书，并在浏览器或程序中使用，纯`shell`脚本，调用`openssl`签发。

## 效果

![](https://static.zahui.fan/images/202411071641322.png)

![](https://static.zahui.fan/images/202411071641461.png)

![](https://static.zahui.fan/images/202411071641156.png)


## 首先制作CA证书

CA证书直接执行`mk_ca.sh`即可，会在`ssl`目录中生成 `ca.crt`(证书) `ca.key`(私钥) `ca.srl` 这几个文件，其中自己的操作系统需要信任`ca.crt`证书文件。

## 制作证书

制作证书，修改`mk_cert.sh`脚本中的`v3.ext`关联的域名、ip等

## 信任CA证书


参考: [制作和使用自签名证书](https://zahui.fan/posts/097e5b7c/) 里面的 **配置客户端信任 CA 证书** 章节


## 配置证书

### Nginx

Nginx配置证书，只需要把 证书.key 和 证书.crt 配置到Nginx中即可。

```conf
server {
        listen 443 ssl;
        server_name localhost;
        ssl_certificate ssl/server.crt;         # 配置证书位置
        ssl_certificate_key ssl/server.key;     # 配置秘钥位置
        ssl_client_certificate ssl/ca.crt;
        ssl_verify_client on;
        ssl_crl ssl/ca.crl;
        ssl_session_timeout 5m;
        ssl_protocols SSLv2 SSLv3 TLSv1 TLSv1.1 TLSv1.2;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
        ssl_prefer_server_ciphers on;
        root html;
        index index.html;
        location / {
                try_files $uri $uri/ =404;
        }
}

```