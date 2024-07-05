# [`csi-driver-nfs`](https://github.com/kubernetes-csi/csi-driver-nfs)

>This driver allows Kubernetes to access NFS server on Linux node.

## [Install/Teardon by Helm](https://github.com/kubernetes-csi/csi-driver-nfs/blob/master/charts/README.md)

### [`csi-driver-nfs.sh`](csi-driver-nfs.sh)

Available `subDir` params:

- `${pvc.metadata.name}`
- `${pvc.metadata.namespace}`
- `${pv.metadata.name}`

__Delete v. Retain__ behavior __on PVC delete__ 

```yaml
controller:
  ...
  defaultOnDeletePolicy: delete # Affects NFS subDir : delete or retain
...
storageClass:
  ...
  reclaimPolicy: Delete # Affects PV only : Delete or Retain
```
- See [__`values.lime.yaml.yaml`__](values.lime.yaml.tpl)


## Install/Teardown by Bash Script

***Why?***

__Install__

Option 1.

```bash
ver=v4.11.0
base=https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/$ver/deploy
curl -skSL $base/install-driver.sh | bash -s $ver --
```

Option 2.

```bash
ver=v4.11.0
git clone https://github.com/kubernetes-csi/csi-driver-nfs.git
cd csi-driver-nfs
./deploy/install-driver.sh $ver local
```

Status

```bash
kubectl -n kube-system get pod -o wide -l app=csi-nfs-controller
kubectl -n kube-system get pod -o wide -l app=csi-nfs-node
```

__Teardown__


Option 1.

```bash
ver=v4.11.0
base=https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/$ver/deploy
curl -skSL $base/uninstall-driver.sh | bash -s $ver --
```

Option 2.

```bash
ver=v4.11.0
git clone https://github.com/kubernetes-csi/csi-driver-nfs.git
cd csi-driver-nfs
./deploy/uninstall-driver.sh $ver local
```

## Lab

__Install__

@ `csi/csi-driver-nfs`

```bash
bash csi-driver-nfs repo
bash csi-driver-nfs.sh pull 
bash csi-driver-nfs.sh values
bash csi-driver-nfs.sh diffValues
bash csi-driver-nfs.sh template
bash csi-driver-nfs.sh install
bash csi-driver-nfs.sh manifest
bash csi-driver-nfs.sh diffManifest
bash csi-driver-nfs.sh teardown
```

@ Project root

```bash
make csi-nfs
```

Then &hellip;

@ `csi/csi-driver-nfs`

```bash
☩ kubectl --namespace=kube-system get pods --selector="app.kubernetes.io/instance=nfs-csi"
NAME                                  READY   STATUS    RESTARTS   AGE
csi-nfs-controller-577b7b4f89-g7q2f   5/5     Running   0          24m
csi-nfs-node-lzg7d                    3/3     Running   0          24m
csi-nfs-node-scsvq                    3/3     Running   0          24m
csi-nfs-node-sjkm7                    3/3     Running   0          24m

☩ helm list -n kube-system
NAME    NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                   APP VERSION
nfs-csi kube-system     1               2025-09-14 15:31:41.877838175 -0400 EDT deployed        csi-driver-nfs-4.11.0   4.11.0

☩ k get sc
NAME                PROVISIONER      RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
nfs-csi (default)   nfs.csi.k8s.io   Delete          Immediate           true                   21m
```

```bash
☩ k apply -f csi-driver-nfs-test-secure.yaml
persistentvolumeclaim/test-nfs-csi-secure-pvc created
pod/test-nfs-csi-secure-pod created

☩ kw
...
test-nfs-csi-secure-pod   1/1     Running   0          4s    10.244.78.254   a2     <none>           <none>
```

Verify @ NFS server 

```bash
☩ ssh a0 sudo ls -halRZ /srv/nfs/k8s
...
/srv/nfs/k8s/nfs-csi/pvc-cc250e59-1684-47a8-94c7-376475297f2c/default/test-nfs-csi-secure-pvc/test-nfs-csi-secure-pod:
total 0
drwxrwx---+ 2  200        200 system_u:object_r:public_content_rw_t:s0 160 Sep 14 15:50 .
drwxrws---+ 3 root ad-nfsanon system_u:object_r:public_content_rw_t:s0  37 Sep 14 15:50 ..
-rw-rw----. 1  200        200 system_u:object_r:public_content_rw_t:s0   0 Sep 14 15:50 hello.from.u.200@test-nfs-csi-secure-pod@2025-09-14T19.50.17+00.00
-rw-rw----. 1  200        200 system_u:object_r:public_content_rw_t:s0   0 Sep 14 15:50 test-nfs-csi-secure-pod-19.50.17
-rw-rw----. 1  200        200 system_u:object_r:public_content_rw_t:s0   0 Sep 14 15:50 test-nfs-csi-secure-pod-19.50.32

```