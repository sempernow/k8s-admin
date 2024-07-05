#!/usr/bin/env bash
#######################################################
# Install/Delete kube-prometheus-stack by Helm method
# GitHub : https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
#######################################################
set -euo pipefail

export RELEASE='kps'
export NAMESPACE='kube-metrics'

install(){

    # Helm binary if not already
    v=v3.17.3
    what=linux-amd64
    url=https://get.helm.sh/helm-$v-$what.tar.gz
    type -t helm > /dev/null 2>&1 &&
        helm version |grep $v > /dev/null 2>&1 || {
            echo '  INSTALLing helm'
            curl -sSfL $url |tar -xzf - &&
                sudo install $what/helm /usr/local/bin/ &&
                    rm -rf $what &&
                        echo ok || echo ERR : $?
        }

    # Chart
    v=72.4.0
    repo=prometheus-community
    chart=kube-prometheus-stack
    values=values.minimal.yaml # Minimal diff for core functionality.
    opts="-n $NAMESPACE --create-namespace --version $v -f $values" 
    helm repo add $repo https://$repo.github.io/helm-charts --force-update &&
        helm show values $repo/$chart --version $v |tee values.yaml &&
            helm template $RELEASE $repo/$chart $opts |tee helm.template.yaml &&
                helm upgrade $RELEASE $repo/$chart --install $opts

    grep image: helm.template.yaml |sort -u |sed 's/^[[:space:]]*//g' |cut -d' ' -f2 |sed 's/"//g' >kps.images.log
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

pushd ${BASH_SOURCE%/*} || pushd . || exit 1
"$@" || echo "❌  ERR : $?" >&2
popd
