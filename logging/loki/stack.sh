#!/usr/bin/env bash
###################################################################
# Grafana Loki project : Install by Helm
# https://github.com/grafana/loki/tree/main/production/helm/loki
###################################################################

RELEASE=loki

upgrade(){
    v=6.29.0 # App Version: 3.4.2
    repo=grafana
    chart=loki
    values=values.v0.0.1.yaml
    opts="--version $v -f $values" 
    helm repo add $repo https://grafana.github.io/helm-charts --force-update &&
        helm show values $repo/$chart --version $v |tee values.yaml &&
            helm template $RELEASE $repo/$chart $opts |tee helm.template.yaml &&
                helm upgrade $RELEASE $repo/$chart --install $opts
}

delete(){
    helm delete $RELEASE
}

pushd ${BASH_SOURCE%/*} || pushd . || exit 1
"$@" || echo ERR $?
popd
