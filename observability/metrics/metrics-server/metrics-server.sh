#!/usr/bin/env bash
# https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/
# https://github.com/kubernetes-sigs/metrics-server

apply(){
    [[ -f components.yaml ]] ||
    curl -sSLO https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    # See deploy.metrics-server.yaml : A modified components.yaml
    kubectl apply -f components.yaml --wait=true
    kubectl apply -f deploy.metrics-server.yaml --wait=true

    kubectl top pod -A
    kubectl top node
}

delete(){
    kubectl delete -f deploy.metrics-server.yaml
    kubectl delete -f components.yaml
}

pushd ${BASH_SOURCE%/*} || exit 1
"$@" || code=$?
popd
[[ $code ]] && echo " ERR : $code" || echo
exit
