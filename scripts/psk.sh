#!/usr/bin/env bash
_psk ()
{
    k8s='
            containerd
            dockerd
            etcd
            kubelet
            kube-apiserver
            kube-controller-manager
            kube-scheduler
            kube-proxy
        '
    function _ps ()
    {
        [[ -n "$1" ]] || exit 1
        echo @ $1
        ps -ax -o command |grep -- "$1 " |tr ' ' '\n' |grep -- -- |grep -v grep
    };
    export -f _ps
    [[ -n $1 ]] && _ps $1 || echo $k8s |xargs -n 1 /bin/bash -c '_ps "$@"' _
}
_psk "$@" || echo ERR: $?

