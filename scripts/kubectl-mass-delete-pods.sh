#!/usr/bin/env bash

echo "ℹ️ This method is DEPRICATED : Use function prune @ make.recipes.sh"
exit 0

[[ $1 ]] || exit 1
[[ ${1,,} =~ 'running' ]] && exit 2

kubectl get pod -A -o wide 
    |grep "$1" \
    |awk '{print $1,$2}' \
    |xargs -n2 /bin/bash -c 'kubectl -n $1 delete pod $2' _
