#!/usr/bin/env bash
# NFS Subdir External Provisioner
# An NFS client requiring an existing NFS server.
# Dynamically provisions a PersistentVolume (pv) per PersistentVolumeClaim (pvc):
# @ SERVER:MOUNT/${namespace}-${pvcName}-${pvName}
# https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner
type -t helm || exit 111

# Add the provisioner's Helm repo to local helm 
server=a0.lime.lan
chart=nfs-subdir-external-provisioner
origin=https://kubernetes-sigs.github.io
helm repo add $chart $origin/$chart
helm repo update $chart

# Configure the release
nfs_server_ip="$(nslookup $server |grep Address |tail -n1 |cut -d' ' -f2)"
ping -c1 -w2 $nfs_server_ip || exit 11

nfs_export=/srv/nfs/k8s
release=nfs-provisioner
ns=kube-system
values=values.lime.yaml

# # Generate the manifest locally
# helm template $release $chart/$chart \
#     --namespace $ns \
#     --set nfs.server=$nfs_server_ip \
#     --set nfs.path=$nfs_export \
#     --set storageClass.name=nfs-client \
#     --set storageClass.defaultClass=true \
#     --set provisioner=cluster.local/$release \
#     --set serviceAccount.name=$release \
#     --set securityContext.runAsUser=50000 \
#     --set securityContext.runAsGroup=322202601 \
#     |tee helm.template.$release.yaml

# Same, but declarative ($values) v. imperative (--set *) method 
helm template $release $chart/$chart \
    --namespace $ns \
    --values $values \
    |tee helm.template.$release.yaml

# Install the provisioner
#kubectl apply -f $manifest
# helm upgrade $release $chart/$chart \
#     --install \
#     --wait \
#     --namespace $ns \
#     --set nfs.server=$nfs_server_ip \
#     --set nfs.path=$nfs_export \
#     --set storageClass.name=nfs-client \
#     --set storageClass.defaultClass=true \
#     --set provisioner=cluster.local/$release \
#     --set serviceAccount.name=$release \
#     --set securityContext.runAsUser=50000 \
#     --set securityContext.runAsGroup=322202601 \
#     |tee helm.install.$release.log

# Install by declarative upgrade method
helm upgrade $release $chart/$chart \
    --install \
    --wait \
    --namespace $ns \
    --values $values || exit 22

# Capture the running manifest 
helm -n $ns get manifest $release |tee helm.manifest.$release.yaml

# Inspect the difference (delcared v. running)
# Want no difference
diff helm.template.$release.yaml helm.manifest.$release.yaml

helm -n $ns status $release

exit $?
##########

# Test dynamic provisioning : Create a claim (pvc) and a pod having a mount that refernces it.
# Want PersistentVolume (pv) and its physical/host store (subdir) to be created dynamically.
base=https://raw.githubusercontent.com/kubernetes-sigs/nfs-subdir-external-provisioner/master/deploy
pvc=test-claim.yaml
pod=test-pod.yaml 
curl -fsSLO $base/$pvc && echo ok || echo ERR: $?
curl -fsSLO $base/$pod && echo ok || echo ERR: $?
kubectl apply -f $pvc --wait 
kubectl apply -f $pod --wait

# Attempts to modify default UID:GID and/or MODE at StorageClass have no affect. 
# Must declare at NFS-server /etc/exports
# If NFSv3, then config is simple. If NFSv4, then it's more complicated.
# 
# sc=nfs-client
# Patch is forbidden:
#kubectl patch storageclass $sc -p '{"parameters": {"mountOptions": "dir_mode=0770,file_mode=0660"}}'
# So, capture/delete/edit/create:
# kubectl get sc $sc -o yaml |tee sc.$sc.yaml
# vi sc.$sc.yaml 
# kubectl create -f sc.$sc.yaml