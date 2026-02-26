#!/usr/bin/env bash
#######################################################
# Install/Delete kube-prometheus-stack by Helm method
# GitHub : https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
#######################################################
set -euo pipefail

installHelm(){
    ver=v3.17.3
    what=linux-amd64
    url=https://get.helm.sh/helm-${ver}-$what.tar.gz
    type -t helm > /dev/null 2>&1 &&
        helm version |grep $VER > /dev/null 2>&1 || {
            echo '  INSTALLing helm'
            curl -sSfL $url |tar -xzf - &&
                sudo install $what/helm /usr/local/bin/ &&
                    rm -rf $what &&
                        echo ok || echo ERR : $?
        }
}

export RELEASE='kps'
export NAMESPACE='kube-metrics'
# Chart
VER=82.4.0
REPO=prometheus-community
CHART=kube-prometheus-stack
VALUES=values.minimal.yaml # Minimal diff for core functionality.
OPTS="-n $NAMESPACE --create-namespace --version $VER -f $VALUES" 
ARCHIVE=${CHART}-$VER.tgz

pull(){
    [[ $(find . -type f -iname '*.tgz') ]] ||
        helm pull $REPO/$CHART
    find . -type f -iname '*.tgz' -printf "%P\n"
}
template(){
    helm template $RELEASE $REPO/$CHART $OPTS |tee helm.template.yaml
}
imagesExtract(){
    template
    echo -e '\n=== Chart images'
    grep image: helm.template.yaml |
        sort -u |
        sed 's/^[[:space:]]*//g' |
        cut -d' ' -f2 |sed 's/"//g' |
        tee kps.images
}
valuesExtract(){
    template >/dev/null
    echo -e '\n=== (Sub)Chart values file(s)'
    tar -tvf $ARCHIVE  |
        grep values.yaml |
        awk '{print $6}' |
        xargs -n1 tar -xaf $ARCHIVE &&
            find $CHART -type f -exec /bin/bash -c '
                fname=${1%/*};fname=${fname##*/};echo $fname;mv $1 values.$fname.yaml
            ' _ {} \; && rm -rf $CHART
    find . -type f -iname 'values.*.yaml'
}
install(){
    helm repo add $REPO https://$REPO.github.io/helm-charts --force-update &&
        helm show values $REPO/$CHART --version $VER |tee values.yaml &&
            helm template $RELEASE $REPO/$CHART $OPTS |tee helm.template.yaml &&
                helm upgrade $RELEASE $REPO/$CHART --install $OPTS
}
access(){
    _access(){
        ns=${NAMESPACE:-kube-metrics}
        target=${1:-grafana} 
        labels="app.kubernetes.io/name=$target,app.kubernetes.io/instance=$RELEASE"

        echo === ${target^}
        kubectl -n $ns get svc |grep $target >/dev/null 2>&1 || return $?

        case "$target" in
            grafana)        svc=kps-grafana; pmap=3000:80; path=login;;
            prometheus)     svc=kps-kube-prometheus-stack-prometheus; pmap=9090:9090; path=query;;
            alertmanager)   svc=kps-kube-prometheus-stack-alertmanager; pmap=9093:9093; path='';;
            node-exporter)  svc=kps-prometheus-node-exporter; pmap=9100:9100; path='';;
            *) echo "❌  UNKNOWN target: $target" >&2; return 2;;
        esac
        #echo -e "svc: $svc\npmap: $pmap\npath: $path"

        pgrep -f "port-forward .* $svc $pmap" >/dev/null ||
            kubectl -n "$ns" port-forward svc/$svc $pmap >/dev/null 2>&1 &

        sleep 1

        curl -sfIX GET "http://localhost:${pmap%:*}/$path" |head -1 ||
            echo "❌  NOT up on :${pmap%:*}"
    }
    for svc in grafana prometheus alertmanager
    do 
        _access $svc || {
            echo "❌  NO Service having '*${svc}*' in name"
            continue
        }
        [[ $svc == 'grafana' ]] && {
            port=3000
            curl --max-time 3 -sfIX GET http://localhost:$port/login |grep HTTP &&
                echo Origin : http://localhost:$port &&
                pass="$(
                    kubectl -n $NAMESPACE get secrets $RELEASE-grafana -o jsonpath="{.data.admin-password}" \
                    |base64 -d
                )" &&
                echo Login  : admin:$pass ||
                echo FAILed at GET http://localhost:${port}
        }
    done
}
delete(){
    helm delete $RELEASE -n $NAMESPACE
}

pushd ${BASH_SOURCE%/*} >/dev/null || pushd . >/dev/null || exit 1
"$@" || echo "❌  ERR : $?" >&2
popd >/dev/null
