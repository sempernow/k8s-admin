#!/usr/bin/env bash
## kubelet configuration : systemd drop-in for Node Allocatable params
## https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/ 
## Reserve ample resources for control plane, especially if node is dual use.
## https://unofficial-kubernetes.readthedocs.io/en/latest/tasks/administer-cluster/reserve-compute-resources/
## See scripts/etc.systemd.system.kubelet.service.10-reserved-resources.conf
file=10-reserved-resources.conf
dir=/etc/systemd/system/kubelet.service.d
sudo mkdir -p $dir &&
    sudo cp -p $file $dir/$file &&
        sudo chown 0:0 $dir/$file &&
            sudo chmod 644 $dir/$file &&
                sudo ls -hl $dir/$file &&
                    sudo cat $dir/$file
