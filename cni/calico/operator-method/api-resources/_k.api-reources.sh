#!/usr/bin/env bash
kubectl api-resources --no-headers \
    |grep -ie calico -ie tigera \
    |awk '{print $1,$NF}' \
    |xargs -n2 /bin/bash -c '
        kind=$2
        list="$(kubectl get $1 -A --no-headers 2>&1 |cut -d" " -f1)"
        [[ "$(echo "$list" |grep "No")" ]] || printf "$kind %s\n" $list
    ' _ |xargs -n2 /bin/bash -c 'kubectl get $1 $2 -o yaml |tee $1.$2.yaml' _
