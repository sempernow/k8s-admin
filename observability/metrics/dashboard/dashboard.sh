#!/usr/bin/env bash
# https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/
# https://chatgpt.com/share/6769c50f-b62c-8009-bb86-46472b9251d1 
set -euo pipefail

ok(){
    v=v2.7.0
    manifest=recommended.yaml
    [[ -r $manifest ]] ||
        curl -fsSLO https://raw.githubusercontent.com/kubernetes/dashboard/$v/aio/deploy/$manifest
        
    [[ -r $manifest ]] && kubectl apply -f $manifest

    sa=kubernetes-dashboard
    ns=$sa
    cr=cluster-admin
    kubectl get clusterrolebinding $sa-admin || 
        kubectl create clusterrolebinding $sa-admin \
        --clusterrole=$cr \
        --serviceaccount=$ns:$sa

    kubectl -n $ns create token $sa

    printf "\n  %s\n" Access @ http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

    kubectl proxy
}

pushd ${BASH_SOURCE%/*} || exit 1
ok || code=$?
popd
[[ $code ]] && echo " ERR : $code" || echo
exit $code
