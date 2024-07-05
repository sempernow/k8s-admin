#!/usr/bin/env bash

ok(){
    v=0.25.0
    repo=aqua
    chart=trivy-operator
    release=$chart
    helm repo add $repo https://aquasecurity.github.io/helm-charts/ ||
        helm repo upadate
    helm upgrade --install --atomic \
        --version $v \
        --values values.yaml \
        --create-namespace \
        --namespace $release \
        $release $repo/$chart
}
ok 
