#!/usr/bin/env bash
ok(){
    # Install helm (idempotent)
    # https://github.com/helm/helm/releases
    ver=v3.18.6
    arch=linux-amd64
    url=https://get.helm.sh/helm-$ver-$arch.tar.gz
    type -t helm >/dev/null 2>&1 &&
        helm version 2>/dev/null |grep -q $ver || {
            curl -sSfL $url |tar -xzf - &&
                sudo install $arch/helm /usr/local/bin/ &&
                    rm -rf $arch ||
                        return $?
        }

    helm version
}
ok || exit $?
