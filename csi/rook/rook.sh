#!/usr/bin/env bash

up(){
    # Install Rook
    # https://rook.github.io/docs/rook/latest-release/Getting-Started/quickstart/#prerequisites
    [[ $(type -t git) ]] || exit 11
    v=1.16.0
    manifests='
        crds
        common
        operator
        cluster
        toolbox
        dashboard-external-http
        dashboard-external-https
        dashboard-ingress-https
        dashboard-loadbalancer
        object
        object-user
    '
    [[ -d examples ]] || {
        mkdir -p examples/csi/rbd
        # https://github.com/rook/rook/blob/release-1.16/deploy/examples
        git clone --single-branch --branch v$v https://github.com/rook/rook.git
        printf "%s\n" $manifests |xargs -n1 /bin/bash -c '
            cp -p rook/deploy/examples/$1.yaml examples/$1.yaml
        ' _
        [[ -d rook/.git ]] && rm -rf rook
    }
    pushd examples || return 22
    kubectl create -f crds.yaml -f common.yaml -f operator.yaml
    kubectl create -f cluster.yaml
    kubectl create -f object.yaml -f object-user.yaml
    kubectl apply -f toolbox.yaml

    popd 
    # RBD : example/csi/rbd/storageclass.yaml
    kubectl apply -f storageclass-rbd.yaml 
    # CephFS : example/filesystem.yaml
    kubectl apply -f storageclass-cephfs.yaml 
}
# https://rook.io/docs/rook/latest-release/Getting-Started/ceph-teardown/#cleaning-up-a-cluster
down(){
    # Destroy the data
    kubectl -n rook-ceph patch cephcluster rook-ceph --type merge -p '{"spec":{"cleanupPolicy":{"confirmation":"yes-really-destroy-data"}}}'

    kubectl delete -n rook-ceph cephblockpool replicapool
    kubectl delete storageclass rook-ceph-block
    kubectl delete storageclass csi-cephfs
    pushd examples || return 11
    for manifest in toolbox object object-user cluster operator common crds;do
        [[ -r $manifest.yaml ]] &&
            kubectl delete -f $manifest.yaml
    done
    popd
    kubectl delete ns rook-ceph
}
host_teardown(){
    # Working at TARGET NODEs, delete all NDBs (Network Block Device)s
    #type -t qemu-nbd || dnf install -y qemu-nbd
    #for nbd in /dev/nbd*; do
    #    qemu-nbd --disconnect $nbd
    #done
    # Delete state
    rm -rf /var/lib/rook

    # Wipe block device 
    rbd=sdb
    sudo wipefs --all /dev/sdb && sudo dd if=/dev/zero of=/dev/${rbd} bs=1M count=10
}

pushd ${BASH_SOURCE%/*} || pushd . || exit 1
"$@" || code=$?
popd
[[ $code ]] && echo " ERR : $code" || echo
exit $code
