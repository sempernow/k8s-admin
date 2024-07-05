#!/usr/bin/env bash
[[ -r $1 ]] || {
    echo "⚠️  ERR : REQUIREs arg: PATH_TO_P7B_FILE" >&2

    exit 1
}
openssl pkcs7 -print_certs -in $1 -out $1.2.pem
