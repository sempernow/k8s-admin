## Create using values.yaml (chart default) as source,
## deleting all keys except those modified for the target release.

feature:
  propagateHostMountOptions: true

controller:
  runOnControlPlane: true
  enableSnapshotter: true
  defaultOnDeletePolicy: delete # Affects NFS subDir : delete or retain

externalSnapshotter:
  enabled: true

storageClass:
  create: true
  name: nfs-csi
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
  parameters:
    server: $NFS_SERVER
    share: $NFS_EXPORT_PATH
    subDir: /nfs-csi/${pv.metadata.name}/${pvc.metadata.namespace}/${pvc.metadata.name}
    mountPermissions: "0"
  reclaimPolicy: Delete # Affects PV only : Delete or Retain
  volumeBindingMode: Immediate
  mountOptions:
    - nfsvers=4.2
