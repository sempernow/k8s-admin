#!/usr/bin/env bash
###################################################################
# Install yq : Releases https://github.com/mikefarah/yq/releases/
###################################################################

ok(){
    # yq
    ver=v4.47.2
    bin=yq_linux_amd64
    base=https://github.com/mikefarah/yq/releases/download/$ver

    yq --version |grep $ver &&
        return 0

    curl -fsSLO $base/$bin.tar.gz &&
        tar -xvf $bin.tar.gz &&
            install $bin /usr/local/bin/yq &&
                cp yq.1 /usr/share/man/man1/ &&
                    rm $bin yq.1 $bin.tar.gz install-man-page.sh

    type yq
    yq --version 
}
ok

