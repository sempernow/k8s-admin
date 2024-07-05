#!/usr/bin/env bash
###################################################################
# kube-router : https://github.com/cloudnativelabs/kube-router/
# ARGs: 
#   _install [pod_ntwk_only | replace_kube_proxy]
#   _teardown
###################################################################
export BASE=https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset
export ALL=kubeadm-kuberouter-all-features.yaml
export POD=kubeadm-kuberouter.yaml

_kubeproxy_cleanup(){
    # cleanup kube-proxy's iptables and such
    img=$(kubectl get ds kube-proxy -o jsonpath='{.spec.template.spec.containers[].image}')
    [[ $(echo $img |grep 'kube-proxy') ]] ||
        img=k8s.gcr.io/kube-proxy-amd64:v1.28.2
    type -t ctr || return $?
    sudo ctr images pull $img &&
        sudo ctr run --rm --privileged --net-host \
            --mount type=bind,src=/lib/modules,dst=/lib/modules,options=rbind:ro \
            $img kube-proxy-cleanup kube-proxy --cleanup || return $?
}
_install(){
    type -t kubectl || return $?
    replace_kube_proxy(){
        # Service Proxy (kube-proxy), Firewall, and Pod Network and Policy
        [[ -f $ALL ]] || curl -sSLO $BASE/$ALL || return $?
        kubectl apply -f $ALL &&
            kubectl patch ds -n kube-system kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"not-kuberouter": "true"}}}}}' &&
            _kubeproxy_cleanup || return $?
    }
    pod_ntwk_only(){
        # Pod Network and Policy
        [[ -f $POD ]] || curl -sSLO $BASE/$POD || return $?
        kubectl apply -f $POD
    }
    either(){
        replace_kube_proxy || pod_ntwk_only
    }

    "${1:-either}" || return $?
}
_teardown(){
    kubectl delete -f $ALL
    kubectl delete -f $POD || echo ERR : kube-router $FUNCNAME : $?
}

pushd ${BASH_SOURCE%/*} || pushd . || exit 1
"$@" || code=$?
popd
[[ $code ]] && echo " ERR : $code" || echo
exit $code
