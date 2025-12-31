#!/usr/bin/env bash
[[ "$(id -u)" -ne 0 ]] && {
    echo "❌  ERR : MUST run as root" >&2
    exit 11
}
[[ -r /etc/kubernetes/kubeadm-config.yaml ]] || {
    echo "❌  ERR : Required config NOT EXIST : /etc/kubernetes/kubeadm-conf.yaml" >&2
    exit 12
}

# Generate super-admin.conf
kubeadm kubeconfig user \
    --config /etc/kubernetes/kubeadm-config.yaml \
    --client-name kubernetes-super-admin \
    --org system:masters \
    > super-admin.conf

# Install if not already
ls /etc/kubernetes/super-admin.conf 2>/dev/null &&
    echo "⚠️  WARNING : Already installed : NO CHANGE" >&2 ||
        install -p --mode=600 super-admin.conf /etc/kubernetes/

rm super-admin.conf

