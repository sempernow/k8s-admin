ok(){
    # cleanup kube-proxy's iptables and such
    img=$(kubectl get ds kube-proxy -o jsonpath='{.spec.template.spec.containers[].image}')
    [[ $(echo $img |grep 'kube-proxy') ]] ||
        img=k8s.gcr.io/kube-proxy-amd64:v1.28.2
    type -t ctr || return $?
    sudo ctr images pull $img &&
        sudo ctr run --rm --privileged --net-host \
            --mount type=bind,src=/lib/modules,dst=/lib/modules,options=rbind:ro \
            $img kube-proxy-cleanup kube-proxy --cleanup ||
                return $?
}

ok "$@" || echo ERR : $?
