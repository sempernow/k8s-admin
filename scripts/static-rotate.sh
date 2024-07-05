#!/usr/bin/env bash

[[ $(whoami) == 'root' ]] || {

  exit 11
}

manifests=/etc/kubernetes/manifests
tmp=/tmp/k8s/static-pods

stop() {
    mkdir -p $tmp || exit 22
    find $manifests -type f -iname '*.yaml' -exec mv {} $tmp/ \; 
}
start(){
    [[ -d $tmp ]] || exit 22
    find $tmp -type f -iname '*.yaml' -exec mv {} $manifests/ \;
}

"$@" || echo ERR

find $manifests -type f -iname '*.yaml' 
