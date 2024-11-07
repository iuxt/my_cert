
## 首先制作CA证书

CA证书直接执行`mk_ca.sh`即可，会在`ssl`目录中生成 `ca.crt`(证书) `ca.key`(私钥) `ca.srl` 这几个文件，其中自己的操作系统需要信任`ca.crt`证书文件。

## 制作证书

制作证书，修改`mk_cert.sh`脚本中的`v3.ext`关联的域名、ip等

## 信任CA证书


参考: [制作和使用自签名证书](https://zahui.fan/posts/097e5b7c/) 里面的 **配置客户端信任 CA 证书** 章节


