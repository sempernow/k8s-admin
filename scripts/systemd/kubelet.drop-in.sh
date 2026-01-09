#!/usr/bin/env bash
## kubelet configuration : systemd drop-in for Node Allocatable params
## https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/ 
## Reserve ample resources for control plane, especially if node is dual use.
## https://unofficial-kubernetes.readthedocs.io/en/latest/tasks/administer-cluster/reserve-compute-resources/
## See scripts/etc.systemd.system.kubelet.service.10-reserved-resources.conf
## ARGs: [ANY to apply the new config]

[[ "$(id -u)" -ne 0 ]] && {
    echo "❌️  ERR : MUST run as root" >&2

    exit 11
}
file=10-reserved-resources.conf
dir=/etc/systemd/system/kubelet.service.d
mkdir -p $dir &&
    cp -p $file $dir/$file &&
        chown 0:0 $dir/$file &&
            chmod 644 $dir/$file &&
                ls -hl $dir/$file &&
                    cat $dir/$file


[[ $1 ]] &&
    echo === Reload/Restart the kubelet service &&
        systemctl daemon-reload &&
            systemctl restart kubelet &&
                systemctl is-active kubelet

