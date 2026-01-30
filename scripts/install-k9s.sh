#!/usr/bin/env bash
# https://github.com/derailed/k9s/releases
ver=v${1:-0.50.18}
pkg=k9s_linux_amd64
curl -sSL https://github.com/derailed/k9s/releases/download/$ver/$pkg.tar.gz |
    tar -C /tmp -xzf - &&
        sudo install /tmp/k9s /usr/local/bin/
