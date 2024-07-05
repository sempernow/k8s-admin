#!/usr/bin/env bash

ok(){
    # Per-node cleanup of kube-proxy's iptables and such.
    img=$(kubectl get -n kube-system ds kube-proxy -o jsonpath='{.spec.template.spec.containers[].image}')
    [[ $(echo $img |grep 'kube-proxy') ]] ||
        img=k8s.gcr.io/kube-proxy-amd64:v1.29.6
    type -t ctr || return $?
    ctr images pull $img &&
        ctr run --rm --privileged --net-host \
            --mount type=bind,src=/lib/modules,dst=/lib/modules,options=rbind:ro \
            $img kube-proxy-cleanup kube-proxy --cleanup || return $?
}
ok 
