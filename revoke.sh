#!/bin/bash

touch ca/index.txt

echo "01" > ca/crlnumber
openssl ca  -config openssl.cnf -cert ca/ca.crt  -keyfile  ca/ca.key  -revoke ssl/a.com.crt 