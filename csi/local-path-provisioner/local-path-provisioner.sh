#!/usr/bin/env bash
############################################################################ 
# https://github.com/rancher/local-path-provisioner
# https://github.com/rancher/local-path-provisioner/tree/master/examples
############################################################################ 

ok(){
    v=v0.0.30
    base=https://raw.githubusercontent.com/rancher/local-path-provisioner
    manifest=local-path-storage.yaml
    [[ -r $manifest ]] || curl -sSLO $base/$v/deploy/$manifest
    [[ -r $manifest ]] && kubectl apply -f $manifest 
    
    # Usage test : Pod/PVC dynamically create PV 
    # @ /opt/local-path-provisioner/<PVC> on node of pod
    #kubectl create -f $base/master/examples/pvc/pvc.yaml
    #kubectl create -f $base/master/examples/pod/pod.yaml
    kubectl create -f pvc.yaml -f pod.yaml
}

pushd "${BASH_SOURCE%/*}" || pushd . || return 1
ok || echo "ERR: $?"
popd